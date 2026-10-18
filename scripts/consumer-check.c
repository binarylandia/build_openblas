// A program that links libopenblas.a and libflang_rt.runtime.a as a consumer
// does, and checks the results of dgemm_, sgemm_, dsyev_, dgttrf_, and dgttrs_
// against values known in advance. Character arguments carry their hidden
// lengths, as the Fortran calling convention of gfortran and flang passes them.
//
// Prints the OpenBLAS core in use, which OPENBLAS_CORETYPE selects, and exits
// with status 1 after the checks when a result is wrong.

#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void dgemm_(const char *transa, const char *transb, const int *m, const int *n, const int *k,
            const double *alpha, const double *a, const int *lda, const double *b, const int *ldb,
            const double *beta, double *c, const int *ldc, size_t transa_len, size_t transb_len);
void sgemm_(const char *transa, const char *transb, const int *m, const int *n, const int *k,
            const float *alpha, const float *a, const int *lda, const float *b, const int *ldb,
            const float *beta, float *c, const int *ldc, size_t transa_len, size_t transb_len);
void dsyev_(const char *jobz, const char *uplo, const int *n, double *a, const int *lda, double *w,
            double *work, const int *lwork, int *info, size_t jobz_len, size_t uplo_len);
void dgttrf_(const int *n, double *dl, double *d, double *du, double *du2, int *ipiv, int *info);
void dgttrs_(const char *trans, const int *n, const int *nrhs, const double *dl, const double *d,
             const double *du, const double *du2, const int *ipiv, double *b, const int *ldb,
             int *info, size_t trans_len);
char *openblas_get_corename(void);

static int failures = 0;

static void fail(const char *what, double got, double expected) {
  printf("FAIL %s: got %.17g, expected %.17g\n", what, got, expected);
  failures++;
}

// Entries are multiples of 1/4 of magnitude at most 5/4, so every product and
// every sum of the GEMM checks below is exact in float and in double, and the
// BLAS result must equal the reference in every summation order.
static double entry(int i, int j, int salt) {
  return (double)(((i * 7 + j * 3 + salt) % 11) - 5) / 4.0;
}

static void check_dgemm_small(void) {
  int n = 2;
  double one = 1;
  double zero = 0;
  double a[4] = {1, 2, 3, 4};
  double c[4] = {0};
  dgemm_("N", "N", &n, &n, &n, &one, a, &n, a, &n, &zero, c, &n, 1, 1);
  const double expected[4] = {7, 10, 15, 22};
  for (int i = 0; i < 4; i++) {
    if (c[i] != expected[i]) fail("dgemm 2x2", c[i], expected[i]);
  }
}

// C = alpha * op(A) * B + beta * C for m x k op(A), k x n B, with odd sizes
// that leave partial blocks in every dimension.
static void check_gemm(const char *trans, int is_double) {
  const int m = 131;
  const int n = 97;
  const int k = 257;
  const int transposed = trans[0] == 'T';
  const int lda = transposed ? k : m;
  double *a = malloc(sizeof(double) * m * k);
  double *b = malloc(sizeof(double) * k * n);
  double *c = malloc(sizeof(double) * m * n);
  double *ref = malloc(sizeof(double) * m * n);
  float *af = malloc(sizeof(float) * m * k);
  float *bf = malloc(sizeof(float) * k * n);
  float *cf = malloc(sizeof(float) * m * n);
  for (int i = 0; i < m; i++) {
    for (int p = 0; p < k; p++) {
      const int index = transposed ? p + i * lda : i + p * lda;
      a[index] = entry(i, p, 1);
      af[index] = (float)a[index];
    }
  }
  for (int p = 0; p < k; p++) {
    for (int j = 0; j < n; j++) {
      b[p + j * k] = entry(p, j, 2);
      bf[p + j * k] = (float)b[p + j * k];
    }
  }
  const double alpha = 1.5;
  const double beta = 0.5;
  for (int i = 0; i < m; i++) {
    for (int j = 0; j < n; j++) {
      double sum = 0;
      for (int p = 0; p < k; p++) sum += entry(i, p, 1) * entry(p, j, 2);
      const double c0 = entry(i, j, 3);
      c[i + j * m] = c0;
      cf[i + j * m] = (float)c0;
      ref[i + j * m] = alpha * sum + beta * c0;
    }
  }
  char what[32];
  if (is_double) {
    dgemm_(trans, "N", &m, &n, &k, &alpha, a, &lda, b, &k, &beta, c, &m, 1, 1);
    snprintf(what, sizeof(what), "dgemm %sN", trans);
  } else {
    const float alphaf = (float)alpha;
    const float betaf = (float)beta;
    sgemm_(trans, "N", &m, &n, &k, &alphaf, af, &lda, bf, &k, &betaf, cf, &m, 1, 1);
    snprintf(what, sizeof(what), "sgemm %sN", trans);
  }
  for (int i = 0; i < m * n; i++) {
    const double got = is_double ? c[i] : (double)cf[i];
    if (got != ref[i]) {
      fail(what, got, ref[i]);
      break;
    }
  }
  free(a);
  free(b);
  free(c);
  free(ref);
  free(af);
  free(bf);
  free(cf);
}

// The second-difference matrix tridiag(-1, 2, -1) of order n has the
// eigenvalues 2 - 2 cos(j pi / (n + 1)), j = 1..n.
static void check_dsyev(void) {
  const int n = 64;
  double *a = calloc((size_t)n * n, sizeof(double));
  double *v = malloc(sizeof(double) * n * n);
  double w[64];
  for (int i = 0; i < n; i++) {
    a[i + i * n] = 2;
    if (i + 1 < n) {
      a[i + 1 + i * n] = -1;
      a[i + (i + 1) * n] = -1;
    }
  }
  memcpy(v, a, sizeof(double) * n * n);
  int lwork = -1;
  int info = 0;
  double query = 0;
  dsyev_("V", "U", &n, v, &n, w, &query, &lwork, &info, 1, 1);
  lwork = (int)query;
  double *work = malloc(sizeof(double) * lwork);
  dsyev_("V", "U", &n, v, &n, w, work, &lwork, &info, 1, 1);
  if (info != 0) fail("dsyev info", info, 0);
  const double pi = acos(-1.0);
  for (int j = 0; j < n; j++) {
    const double expected = 2 - 2 * cos((j + 1) * pi / (n + 1));
    if (fabs(w[j] - expected) > 1e-12) fail("dsyev eigenvalue", w[j], expected);
  }
  double residual = 0;
  double orthogonality = 0;
  for (int j = 0; j < n; j++) {
    for (int i = 0; i < n; i++) {
      double av = 0;
      double vv = 0;
      for (int p = 0; p < n; p++) {
        av += a[i + p * n] * v[p + j * n];
        vv += v[p + i * n] * v[p + j * n];
      }
      residual = fmax(residual, fabs(av - w[j] * v[i + j * n]));
      orthogonality = fmax(orthogonality, fabs(vv - (i == j ? 1 : 0)));
    }
  }
  if (residual > 1e-12) fail("dsyev residual", residual, 0);
  if (orthogonality > 1e-12) fail("dsyev orthogonality", orthogonality, 0);
  free(a);
  free(v);
  free(work);
}

// A tridiagonal system whose sub-diagonal entries exceed the diagonal ones in
// every third row, so dgttrf pivots, solved for a known x with and without
// transpose. Its condition number is about 18.
static void check_dgttrs(const char *trans) {
  const int n = 100;
  const int nrhs = 1;
  double dl[99];
  double d[100];
  double du[99];
  double du2[98];
  int ipiv[100];
  double x[100];
  double b[100];
  for (int i = 0; i < n; i++) {
    d[i] = (i % 3 == 0) ? 0.5 : 4.0;
    x[i] = i + 1;
  }
  for (int i = 0; i < n - 1; i++) {
    dl[i] = (i % 3 == 0) ? 2.0 : -1.0;
    du[i] = 0.25;
  }
  const int transposed = trans[0] == 'T';
  for (int i = 0; i < n; i++) {
    double sum = d[i] * x[i];
    if (i > 0) sum += (transposed ? du[i - 1] : dl[i - 1]) * x[i - 1];
    if (i + 1 < n) sum += (transposed ? dl[i] : du[i]) * x[i + 1];
    b[i] = sum;
  }
  int info = 0;
  dgttrf_(&n, dl, d, du, du2, ipiv, &info);
  if (info != 0) fail("dgttrf info", info, 0);
  int pivots = 0;
  for (int i = 0; i < n; i++) pivots += ipiv[i] != i + 1;
  if (pivots == 0) fail("dgttrf pivots", 0, 1);
  dgttrs_(trans, &n, &nrhs, dl, d, du, du2, ipiv, b, &n, &info, 1);
  if (info != 0) fail("dgttrs info", info, 0);
  for (int i = 0; i < n; i++) {
    if (fabs(b[i] - x[i]) > 1e-12 * x[i]) {
      fail(transposed ? "dgttrs T" : "dgttrs N", b[i], x[i]);
      break;
    }
  }
}

int main(void) {
  printf("core: %s\n", openblas_get_corename());
  check_dgemm_small();
  check_gemm("N", 1);
  check_gemm("T", 1);
  check_gemm("N", 0);
  check_gemm("T", 0);
  check_dsyev();
  check_dgttrs("N");
  check_dgttrs("T");
  return failures == 0 ? 0 : 1;
}
