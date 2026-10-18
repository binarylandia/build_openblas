# shellcheck shell=bash
#
# Checks of the native archives, which scripts/main runs on every build. They
# read the tools and the target from the environment of the build image: CC, NM,
# READELF, OBJDUMP, READOBJ, TARGET_RUNNER, TARGET_NO_RUN, and CROSS_TARGET.
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
# (libgcc or compiler-rt builtins) of the consumer define, and the Fortran
# runtime functions that flang-rt calls without defining them (on x86_64
# Windows, the COMPLEX(16) reductions, which REAL(16) math would define). The
# link of every object of libopenblas.a in check_consumer shows that no
# function of OpenBLAS needs them.
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
  local undefined_fortran
  undefined_fortran="$(grep -E '^_Fortran' <<<"${flang_rt_external}" || true)"
  local system
  system="$(printf '%s\n%s\n' "${remaining}" "${flang_rt_external}" | grep -vE '^_Fortran' | LC_ALL=C sort -u | sed '/^$/d')"
  local cxx
  cxx="$(grep -E '^(_Z|__cxa_|__gxx_|_Unwind_)' <<<"${system}" | grep -vxE '__cxa_(atexit|finalize)' || true)"
  if [[ -n "${cxx}" ]]; then
    printf 'ERROR: %s and %s need a C++ runtime or an unwinder:\n%s\n' "${lib}" "${flang_rt}" "${cxx}" >&2
    return 1
  fi
  printf 'Symbols that %s and %s take from the system libraries:\n%s\n' "${lib##*/}" "${flang_rt##*/}" "$(paste -sd ' ' - <<<"${system}")"
  if [[ -n "${undefined_fortran}" ]]; then
    printf 'Fortran runtime functions that %s calls without defining them:\n%s\n' "${flang_rt##*/}" "$(paste -sd ' ' - <<<"${undefined_fortran}")"
  fi
}

# Succeed when programs of the target run on the build machine, directly or in
# TARGET_RUNNER.
function target_runs() {
  [[ -z "${TARGET_NO_RUN:-}" ]]
}

# Print the link flags of the programs of the target: musl programs link
# statically, as their consumers do, and run on the build machine without the
# musl loader; glibc programs link the C library dynamically. On macOS and
# Windows, programs link the C runtime as their consumers do by default.
function program_link_flags() {
  case "${CROSS_TARGET}" in
  *-linux-musl) printf -- '-static\n' ;;
  esac
}

# Print the libraries that a program links after the archives: the math and
# thread libraries, which glibc 2.17 keeps out of its C library. libSystem on
# macOS and the UCRT on Windows hold them.
function program_libs() {
  case "${CROSS_TARGET}" in
  *-linux-*) printf -- '-lm\n-lpthread\n' ;;
  esac
}

# Print the file name suffix of the executables of the target.
function executable_suffix() {
  case "${CROSS_TARGET}" in
  *-windows-*) printf '.exe\n' ;;
  esac
}

# Print a macOS version without trailing zero components (11.0.0 -> 11).
function macos_version_normalized() {
  local version="${1}"
  while [[ "${version}" == *.0 ]]; do
    version="${version%.0}"
  done
  printf '%s\n' "${version}"
}

# Print the distinct minimum macOS versions of the Mach-O files in the given
# files (objects, archives, executables), without trailing zero components:
# the version of LC_VERSION_MIN_MACOSX, which the linker writes for deployment
# targets before 10.14, or the minos of LC_BUILD_VERSION.
function macos_versions_min() {
  local versions
  versions="$("${OBJDUMP}" --macho --private-headers "$@" |
    awk '$1 == "cmd" {cmd = $2} cmd == "LC_VERSION_MIN_MACOSX" && $1 == "version" {print $2} cmd == "LC_BUILD_VERSION" && $1 == "minos" {print $2}')" || return
  local version
  for version in ${versions}; do
    macos_version_normalized "${version}"
  done | sort -uV
}

# Fail when an object of the given archives needs a newer macOS than
# MACOSX_DEPLOYMENT_TARGET, which would raise the minimum macOS version of the
# programs that link it. Objects for older versions run on newer ones: the
# C++ objects of flang-rt target macOS 10.7.
function check_macos_version_min() {
  local versions
  versions="$(macos_versions_min "$@")" || return
  local target
  target="$(macos_version_normalized "${MACOSX_DEPLOYMENT_TARGET:?}")"
  if [[ -z "${versions}" ]]; then
    printf 'ERROR: %s have no minimum macOS version\n' "$*" >&2
    return 1
  fi
  if [[ "$(printf '%s\n%s\n' "${versions}" "${target}" | sort -V | tail -1)" != "${target}" ]]; then
    printf 'ERROR: %s have objects for macOS %s, newer than the deployment target %s\n' "$*" "$(paste -sd ' ' - <<<"${versions}")" "${MACOSX_DEPLOYMENT_TARGET}" >&2
    return 1
  fi
  printf 'Minimum macOS versions of the objects of %s: %s\n' "$(basename -a "$@" | paste -sd ' ' -)" "$(paste -sd ' ' - <<<"${versions}")"
}

# Fail when a program needs a shared library or a symbol version beyond what
# the oldest supported system of the target provides: glibc 2.17 and its
# libraries on glibc targets, nothing on musl targets, libSystem on macOS (with
# the minimum macOS version MACOSX_DEPLOYMENT_TARGET), and the system DLLs and
# the UCRT on Windows.
function check_system_dependencies() {
  local program="${1}"
  case "${CROSS_TARGET}" in
  *-apple-darwin)
    check_macos_dependencies "${program}"
    return
    ;;
  *-windows-*)
    check_windows_dependencies "${program}"
    return
    ;;
  esac
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

# Fail unless a macOS program loads no library other than libSystem and has
# the minimum macOS version MACOSX_DEPLOYMENT_TARGET.
function check_macos_dependencies() {
  local program="${1}"
  local dylibs
  dylibs="$("${OBJDUMP}" --macho --dylibs-used "${program}")" || return
  local used
  used="$(sed -n 's/^[[:space:]]*\(\/[^ ]*\) (.*$/\1/p' <<<"${dylibs}")"
  local extra
  extra="$(grep -vxF '/usr/lib/libSystem.B.dylib' <<<"${used}" || true)"
  if [[ -z "${used}" || -n "${extra}" ]]; then
    printf 'ERROR: %s loads libraries beyond libSystem: %s\n' "${program}" "$(paste -sd ' ' - <<<"${used}")" >&2
    return 1
  fi
  local versions
  versions="$(macos_versions_min "${program}")" || return
  if [[ "${versions}" != "$(macos_version_normalized "${MACOSX_DEPLOYMENT_TARGET:?}")" ]]; then
    printf 'ERROR: %s has the minimum macOS version "%s", not the deployment target %s\n' "${program}" "$(paste -sd ' ' - <<<"${versions}")" "${MACOSX_DEPLOYMENT_TARGET}" >&2
    return 1
  fi
  printf 'System dependencies of %s: %s, macOS %s or newer\n' "${program##*/}" "$(paste -sd ' ' - <<<"${used}")" "${MACOSX_DEPLOYMENT_TARGET}"
}

# Fail unless a Windows program imports only KERNEL32.dll and the UCRT through
# its API sets (api-ms-win-crt-*), which every Windows since Windows 10 has and
# Windows 7 and 8 get with the Universal C Runtime update.
function check_windows_dependencies() {
  local program="${1}"
  local imports
  imports="$("${READOBJ:?}" --coff-imports "${program}")" || return
  local dlls
  dlls="$(sed -n 's/^[[:space:]]*Name: //p' <<<"${imports}" | sort -u)"
  local extra
  extra="$(grep -viE '^(kernel32\.dll|api-ms-win-crt-[a-z]+-l1-1-0\.dll)$' <<<"${dlls}" || true)"
  if [[ -z "${dlls}" || -n "${extra}" ]]; then
    printf 'ERROR: %s imports DLLs beyond KERNEL32.dll and the UCRT: %s\n' "${program}" "$(paste -sd ' ' - <<<"${extra}")" >&2
    return 1
  fi
  printf 'System dependencies of %s: %s\n' "${program##*/}" "$(paste -sd ' ' - <<<"${dlls}")"
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
  # Windows programs end their lines with CR LF.
  output="${output//$'\r'/}"
  printf '%s\n' "${output}"
  sed -n 's/^core: //p' <<<"${output}" >&3
}

# Link the consumer check program against the installed archives as a consumer
# does, check its system dependencies, and run it when programs of the target
# run on the build machine: with the core that OpenBLAS detects, and, when the
# program runs in qemu with the max CPU model, which implements every
# instruction set of the target, with each of the given kernel cores, forced
# through OPENBLAS_CORETYPE. A forced core that leaves the detected one in use
# was not applied. Its reported name may differ from the forced one, because
# OpenBLAS reports the first core that shares the kernel table.
function check_consumer() {
  local install_dir="${1}"
  local work_dir="${2}"
  shift 2
  local cores=("$@")
  local program
  program="${work_dir}/consumer-check$(executable_suffix)"
  mkdir -p "${work_dir}"

  local lib="${install_dir}/lib/libopenblas.a"
  local flang_rt="${install_dir}/lib/libflang_rt.runtime.a"
  local link_flags
  link_flags="$(program_libs) $(program_link_flags)"
  # shellcheck disable=SC2086 # the link flags are words
  ${CC} -O2 -o "${program}" "${CONSUMER_CHECK_SOURCE}" "${lib}" "${flang_rt}" ${link_flags} || return
  check_system_dependencies "${program}" || return

  # The program again with every object of libopenblas.a, so that every
  # function of OpenBLAS links with flang-rt and the system libraries alone.
  local program_all
  program_all="${work_dir}/consumer-check-all$(executable_suffix)"
  local whole_archive=("-Wl,--whole-archive" "${lib}" "-Wl,--no-whole-archive")
  if [[ "${CROSS_TARGET}" == *-apple-darwin ]]; then
    whole_archive=("-Wl,-force_load,${lib}")
  fi
  # shellcheck disable=SC2086 # the link flags are words
  ${CC} -O2 -o "${program_all}" "${CONSUMER_CHECK_SOURCE}" "${whole_archive[@]}" "${flang_rt}" ${link_flags} || return
  check_system_dependencies "${program_all}" || return

  if ! target_runs; then
    printf 'Linked %s without running it: %s\n' "${program##*/}" "${TARGET_NO_RUN}"
    return
  fi
  local detected
  detected="$(run_consumer_check "${program}" 3>&1 >&2)" || return
  if [[ "${TARGET_RUNNER}" != qemu-* || "${QEMU_CPU:-}" != "max" ]]; then
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

# Run a program of the target on the build machine: in the emulator or loader
# that TARGET_RUNNER names, or directly when TARGET_RUNNER is empty.
function run_on_target() {
  if ! target_runs; then
    printf 'ERROR: cannot run %s: %s\n' "${1}" "${TARGET_NO_RUN}" >&2
    return 1
  fi
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
