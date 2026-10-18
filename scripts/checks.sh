# shellcheck shell=bash
#
# Checks of the native archives, which scripts/main runs on every build. They
# read the tools and the target from the environment of the build image: CC, NM,
# READELF, TARGET_RUNNER, and CROSS_TARGET.
#

# The program that calls the LAPACK and BLAS routines that consumers call.
CONSUMER_CHECK_SOURCE="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/consumer-check.c"

# Print the prefix that the target puts in front of C symbol names: _ on Mach-O,
# nothing on ELF.
function symbol_prefix() {
  ${CC} -dM -E -x c /dev/null | awk '$2 == "__USER_LABEL_PREFIX__" {print $3}'
}

# Print the names of the undefined (--undefined-only) or defined (--defined-only)
# symbols of an archive, without the symbol prefix of the target, sorted and
# without duplicates.
function archive_symbols() {
  local lib="${1}"
  local selection="${2}"
  local prefix
  prefix="$(symbol_prefix)" || return
  "${NM}" "${selection}" --format=posix "${lib}" |
    awk -v prefix="${prefix}" 'NF >= 2 && $1 !~ /:$/ {
      name = $1
      if (prefix != "" && index(name, prefix) == 1) name = substr(name, length(prefix) + 1)
      print name
    }' |
    LC_ALL=C sort -u
}

# Print the symbols that an archive uses and does not define.
function external_symbols() {
  local lib="${1}"
  LC_ALL=C comm -23 \
    <(archive_symbols "${lib}" --undefined-only) \
    <(archive_symbols "${lib}" --defined-only)
}

# Fail unless libopenblas.a needs no gfortran runtime, flang-rt defines every
# Fortran runtime function that it calls, and neither archive needs a C++
# runtime or an unwinder. Print the other external symbols of both archives,
# which the C library, the math library, and the compiler support library
# (libgcc or compiler-rt builtins) of the consumer define.
function check_fortran_runtime() {
  local lib="${1}"
  local flang_rt="${2}"
  local external
  local flang_rt_external
  local flang_rt_defined
  external="$(external_symbols "${lib}")" || return
  flang_rt_external="$(external_symbols "${flang_rt}")" || return
  flang_rt_defined="$(archive_symbols "${flang_rt}" --defined-only)" || return

  local gfortran
  gfortran="$(grep -E '^_?_gfortran' <<<"${external}" || true)"
  if [[ -n "${gfortran}" ]]; then
    printf 'ERROR: %s calls the gfortran runtime:\n%s\n' "${lib}" "${gfortran}" >&2
    return 1
  fi

  local missing
  missing="$(LC_ALL=C comm -23 <(grep -E '^_Fortran' <<<"${external}" || true) <(printf '%s\n' "${flang_rt_defined}"))"
  if [[ -n "${missing}" ]]; then
    printf 'ERROR: %s calls Fortran runtime functions that %s does not define:\n%s\n' "${lib}" "${flang_rt}" "${missing}" >&2
    return 1
  fi

  local remaining
  remaining="$(LC_ALL=C comm -23 <(printf '%s\n' "${external}") <(printf '%s\n' "${flang_rt_defined}"))"
  local system
  system="$(printf '%s\n%s\n' "${remaining}" "${flang_rt_external}" | LC_ALL=C sort -u | sed '/^$/d')"
  local cxx
  cxx="$(grep -E '^(_Z|__cxa_|__gxx_|_Unwind_)' <<<"${system}" | grep -vxE '__cxa_(atexit|finalize)' || true)"
  if [[ -n "${cxx}" ]]; then
    printf 'ERROR: %s and %s need a C++ runtime or an unwinder:\n%s\n' "${lib}" "${flang_rt}" "${cxx}" >&2
    return 1
  fi
  printf 'Symbols that %s and %s take from the system libraries:\n%s\n' "${lib##*/}" "${flang_rt##*/}" "$(paste -sd ' ' - <<<"${system}")"
}

# Print the link flags of the programs of the target: musl programs link
# statically, as their consumers do, and run on the build machine without the
# musl loader; glibc programs link the C library dynamically.
function program_link_flags() {
  case "${CROSS_TARGET}" in
  *-linux-musl) printf -- '-static\n' ;;
  esac
}

# Fail when a program needs a shared library or a symbol version beyond what
# the oldest supported system of the target provides: glibc 2.17 and its
# libraries on glibc targets, nothing on musl targets.
function check_system_dependencies() {
  local program="${1}"
  local dynamic
  dynamic="$("${READELF}" --dynamic "${program}")" || return
  local needed
  needed="$(sed -n 's/.*(NEEDED).*\[\(.*\)\]$/\1/p' <<<"${dynamic}")"
  case "${CROSS_TARGET}" in
  *-linux-gnu)
    local allowed='^(libc\.so\.6|libm\.so\.6|libpthread\.so\.0|libdl\.so\.2|librt\.so\.1|ld-linux-[a-z0-9_-]+\.so\.[0-9]+)$'
    local extra
    extra="$(grep -vE "${allowed}" <<<"${needed}" || true)"
    if [[ -n "${extra}" ]]; then
      printf 'ERROR: %s needs shared libraries beyond glibc: %s\n' "${program}" "$(paste -sd ' ' - <<<"${extra}")" >&2
      return 1
    fi
    local newest
    newest="$("${READELF}" --version-info "${program}" | grep -oE 'GLIBC_[0-9]+(\.[0-9]+)+' | sort -uV | tail -1)" || return
    if [[ "$(printf '%s\n%s\n' "GLIBC_2.17" "${newest}" | sort -V | tail -1)" != "GLIBC_2.17" ]]; then
      printf 'ERROR: %s needs %s, newer than GLIBC_2.17\n' "${program}" "${newest}" >&2
      return 1
    fi
    printf 'System dependencies of %s: %s, symbols up to %s\n' "${program##*/}" "$(paste -sd ' ' - <<<"${needed}")" "${newest}"
    ;;
  *-linux-musl)
    if [[ -n "${needed}" ]] || "${READELF}" --program-headers "${program}" | grep -q 'INTERP'; then
      printf 'ERROR: %s is not a static executable: it needs %s\n' "${program}" "$(paste -sd ' ' - <<<"${needed}")" >&2
      return 1
    fi
    printf 'System dependencies of %s: none (static)\n' "${program##*/}"
    ;;
  *)
    printf 'ERROR: no system dependency rules for %s\n' "${CROSS_TARGET}" >&2
    return 1
    ;;
  esac
}

# Run the consumer check program, with the core given by OPENBLAS_CORETYPE when
# a core is given, print its output, and print the name of the OpenBLAS core in
# use to the file descriptor 3.
function run_consumer_check() {
  local program="${1}"
  local core="${2:-}"
  local output
  output="$(
    if [[ -n "${core}" ]]; then
      export OPENBLAS_CORETYPE="${core}"
    fi
    run_on_target "${program}" 2>&1
  )" || {
    printf '%s\nERROR: %s failed%s\n' "${output}" "${program}" "${core:+ with OPENBLAS_CORETYPE=${core}}" >&2
    return 1
  }
  printf '%s\n' "${output}"
  sed -n 's/^core: //p' <<<"${output}" >&3
}

# Link the consumer check program against the installed archives as a consumer
# does, check its system dependencies, and run it: with the core that OpenBLAS
# detects, and, when the program runs in an emulator that implements every
# instruction set of the target, with each of the given kernel cores, forced
# through OPENBLAS_CORETYPE. A forced core that leaves the detected one in use
# was not applied. Its reported name may differ from the forced one, because
# OpenBLAS reports the first core that shares the kernel table.
function check_consumer() {
  local install_dir="${1}"
  local work_dir="${2}"
  shift 2
  local cores=("$@")
  local program="${work_dir}/consumer-check"
  mkdir -p "${work_dir}"

  local lib="${install_dir}/lib/libopenblas.a"
  local flang_rt="${install_dir}/lib/libflang_rt.runtime.a"
  local link_flags
  link_flags="$(program_link_flags)"
  # shellcheck disable=SC2086 # the link flags are words
  ${CC} -O2 -o "${program}" "${CONSUMER_CHECK_SOURCE}" "${lib}" "${flang_rt}" -lm -lpthread ${link_flags} || return
  check_system_dependencies "${program}" || return

  # The program again with every object of libopenblas.a, so that every
  # function of OpenBLAS links with flang-rt and the system libraries alone.
  local program_all="${work_dir}/consumer-check-all"
  local whole_archive=("-Wl,--whole-archive" "${lib}" "-Wl,--no-whole-archive")
  # shellcheck disable=SC2086 # the link flags are words
  ${CC} -O2 -o "${program_all}" "${CONSUMER_CHECK_SOURCE}" "${whole_archive[@]}" "${flang_rt}" -lm -lpthread ${link_flags} || return
  check_system_dependencies "${program_all}" || return

  local detected
  detected="$(run_consumer_check "${program}" 3>&1 >&2)" || return
  if [[ -z "${TARGET_RUNNER}" ]]; then
    return
  fi
  local core
  local used
  for core in ${cores[@]+"${cores[@]}"}; do
    used="$(run_consumer_check "${program}" "${core}" 3>&1 >&2)" || return
    if [[ "${used}" == "${detected}" && "${core,,}" != "${detected,,}" ]]; then
      printf 'ERROR: OPENBLAS_CORETYPE=%s left the detected core %s in use\n' "${core}" "${detected}" >&2
      return 1
    fi
  done
}

# Run a program of the target on the build machine: in the emulator that
# TARGET_RUNNER names, or directly when TARGET_RUNNER is empty.
function run_on_target() {
  local runner=()
  read -ra runner <<<"${TARGET_RUNNER?TARGET_RUNNER names the emulator of the target, empty when programs run directly}"
  if ((${#runner[@]} > 0)); then
    "${runner[@]}" "$@"
  else
    "$@"
  fi
}

# Run the level-3 BLAS tests sblat3 and dblat3 of OpenBLAS (built in a test
# directory) for runs given as <core>:<bytes>,...: with the core forced through
# OPENBLAS_CORETYPE, at each SVE vector length in bytes, which qemu-aarch64 sets
# with sve-default-vector-length. Fail on a test failure.
function check_blas3_vector_lengths() {
  local test_dir="${1}"
  local work_dir="${2}"
  shift 2
  rm -rf "${work_dir}"
  mkdir -p "${work_dir}"
  cp "${test_dir}/sblat3" "${test_dir}/dblat3" "${test_dir}/sblat3.dat" "${test_dir}/dblat3.dat" "${work_dir}/" || return
  local run
  local core
  local lengths
  local bytes
  local test
  for run in "$@"; do
    core="${run%%:*}"
    IFS=, read -ra lengths <<<"${run#*:}"
    for bytes in "${lengths[@]}"; do
      for test in sblat3 dblat3; do
        rm -f "${work_dir}/"*.SUMM
        if ! (cd "${work_dir}" && OPENBLAS_CORETYPE="${core}" OPENBLAS_NUM_THREADS=1 \
          QEMU_CPU="max,sve-default-vector-length=${bytes}" run_on_target "./${test}" <"${test}.dat" >/dev/null 2>&1) ||
          grep -qE 'FAIL|FATAL' "${work_dir}/"*.SUMM; then
          printf 'ERROR: %s fails with OPENBLAS_CORETYPE=%s at an SVE vector length of %s bytes:\n' "${test}" "${core}" "${bytes}" >&2
          grep -E 'FAIL|FATAL' "${work_dir}/"*.SUMM >&2
          return 1
        fi
      done
      printf 'Level-3 BLAS tests of %s pass at an SVE vector length of %s bytes\n' "${core}" "${bytes}"
    done
  done
}
