# shellcheck shell=bash
#
# Checks of the native archives, which scripts/main runs on every build. They
# read the tools and the target from the environment of the build image: CC, NM,
# READELF, OBJDUMP, READOBJ, TARGET_RUNNER, TARGET_NO_RUN, CROSS_TARGET, and
# CONSUMER_CC, the C compiler that links the consumer check program as consumers
# of the archives do (default CC).
#

# The program that calls the LAPACK and BLAS routines that consumers call.
CONSUMER_CHECK_SOURCE="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/consumer-check.c"

# The DLLs that programs of x86_64-win7-windows-gnu may import: the C runtime
# msvcrt.dll and the system DLLs that the MinGW GCC driver links by default,
# which every Windows since Windows 7 has.
WINDOWS7_SYSTEM_DLLS=(advapi32.dll kernel32.dll msvcrt.dll shell32.dll user32.dll)

# The exports that msvcrt.dll gained in Windows 8 and 8.1 on x86_64: the
# sections "added in Windows 8" and "added in Windows 8.1 OS system version of
# msvcrt.dll" of mingw-w64-crt/lib-common/msvcrt.def.in of mingw-w64 v14.0.0,
# without the i386 and ARM entries. The C runtime headers declare them for every
# Windows version, so the header comparison of write_windows8_functions does
# not find them. The list after them names no export of any msvcrt.dll.
WINDOWS8_MSVCRT_EXPORTS=(
  _wcstod_l
  __AdjustPointer
  __ExceptionPtrAssign
  __ExceptionPtrCompare
  __ExceptionPtrCopy
  __ExceptionPtrCopyException
  __ExceptionPtrCreate
  __ExceptionPtrCurrentException
  __ExceptionPtrDestroy
  __ExceptionPtrRethrow
  __ExceptionPtrSwap
  __ExceptionPtrToBool
  _W_Getdays
  _W_Getmonths
  _W_Gettnames
  _Wcsftime
)

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
# musl loader; glibc programs link the C library dynamically. Windows 7
# programs link libgcc and winpthreads statically, so that they load only system
# DLLs. On macOS and the other Windows targets, programs link the C runtime as
# their consumers do by default.
function program_link_flags() {
  case "${CROSS_TARGET}" in
  *-linux-musl | *-win7-windows-gnu) printf -- '-static\n' ;;
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
# the minimum macOS version MACOSX_DEPLOYMENT_TARGET), the system DLLs and
# msvcrt.dll of Windows 7 on x86_64-win7-windows-gnu, and the system DLLs and
# the UCRT on the other Windows targets.
function check_system_dependencies() {
  local program="${1}"
  case "${CROSS_TARGET}" in
  *-apple-darwin)
    check_macos_dependencies "${program}"
    return
    ;;
  *-win7-windows-gnu)
    check_windows7_dependencies "${program}"
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

# Fail unless a Windows program imports only the DLLs of WINDOWS7_SYSTEM_DLLS,
# none of the UCRT (ucrtbase.dll, api-ms-win-*), and none of the functions of
# Windows 8 or later that the file WINDOWS8_FUNCTIONS lists
# (write_windows8_functions).
function check_windows7_dependencies() {
  local program="${1}"
  local denied_list="${WINDOWS8_FUNCTIONS:?WINDOWS8_FUNCTIONS names the list of the functions of Windows 8 or later}"
  local imports
  imports="$("${READOBJ:?}" --coff-imports "${program}")" || return
  # Lines of <dll> <function>, with the DLL names in lower case.
  local imported
  imported="$(awk '$1 == "Name:" {dll = tolower($2)} $1 == "Symbol:" {print dll, $2}' <<<"${imports}")"
  local dlls
  dlls="$(awk '$1 == "Name:" {print $2}' <<<"${imports}" | sort -fu)"
  if [[ -z "${dlls}" ]]; then
    printf 'ERROR: %s imports no DLL\n' "${program}" >&2
    return 1
  fi
  local ucrt
  ucrt="$(grep -iE '^(ucrtbase\.dll|api-ms-win-.*)$' <<<"${dlls}" || true)"
  if [[ -n "${ucrt}" ]]; then
    printf 'ERROR: %s imports the UCRT, which Windows 7 lacks without an update: %s\n' "${program}" "$(paste -sd ' ' - <<<"${ucrt}")" >&2
    return 1
  fi
  local extra
  extra="$(LC_ALL=C comm -23 <(tr '[:upper:]' '[:lower:]' <<<"${dlls}" | LC_ALL=C sort -u) <(printf '%s\n' "${WINDOWS7_SYSTEM_DLLS[@]}" | LC_ALL=C sort -u))"
  if [[ -n "${extra}" ]]; then
    printf 'ERROR: %s imports DLLs beyond %s: %s\n' "${program}" "${WINDOWS7_SYSTEM_DLLS[*]}" "$(paste -sd ' ' - <<<"${extra}")" >&2
    return 1
  fi
  local functions
  functions="$(cut -d' ' -f2 <<<"${imported}" | LC_ALL=C sort -u)"
  local denied
  denied="$(LC_ALL=C comm -12 <(printf '%s\n' "${functions}") "${denied_list}")"
  if [[ -n "${denied}" ]]; then
    printf 'ERROR: %s imports functions of Windows 8 or later:\n%s\n' "${program}" "$(grep -wFf <(printf '%s\n' "${denied}") <<<"${imported}")" >&2
    return 1
  fi
  printf 'System dependencies of %s: %s, with none of %s functions of Windows 8 or later among its %s imported functions\n' \
    "${program##*/}" "$(paste -sd ' ' - <<<"${dlls}")" "$(wc -l <"${denied_list}")" "$(wc -l <<<"${functions}")"
}

# Print the include directory of the mingw-w64 headers of CC: the directory of
# the windows.h that the preprocessor includes.
function windows_include_dir() {
  local deps
  deps="$(printf '#include <windows.h>\n' | ${CC} -x c -M -MT deps -)" || return
  local headers
  headers="$(sed -e 's/\\$//' -e 's/[[:space:]]\{1,\}/\n/g' <<<"${deps}" | grep '/windows\.h$')" || {
    printf 'ERROR: %s does not include a windows.h\n' "${CC}" >&2
    return 1
  }
  dirname "$(realpath "${headers%%$'\n'*}")"
}

# Print the names of the functions that an AST dump of clang declares, without
# the implicit declarations of builtins.
function ast_function_names() {
  awk -v q="'" '/FunctionDecl 0x/ && !/ implicit / {
    for (k = 1; k < NF && $k !~ /FunctionDecl$/; k++) {}
    for (i = k + 2; i <= NF; i++) if (substr($i, 1, 1) == q) { print $(i - 1); break }
  }'
}

# Write the names of the functions that one mingw-w64 header declares on its
# own, after the windows.h of the precompiled header, in each configuration of
# write_windows8_functions, into <work dir>/<configuration>/<header>.names.
# Leave a header that does not compile as C in either configuration out, and
# name it in <work dir>/skipped/.
function windows_header_functions() {
  local work_dir="${1}"
  local header="${2}"
  local config
  local defines=()
  local ast
  for config in windows7 newest; do
    read -ra defines <"${work_dir}/${config}.defines"
    # shellcheck disable=SC2086 # CC is a command with arguments
    if ! ast="$(printf '#include <%s>\n' "${header}" |
      ${CC} "${defines[@]}" -include-pch "${work_dir}/${config}.pch" -x c -fsyntax-only \
        -fno-color-diagnostics -Xclang -ast-dump - 2>/dev/null)"; then
      rm -f "${work_dir}/windows7/${header}.names" "${work_dir}/newest/${header}.names"
      : >"${work_dir}/skipped/${header}"
      return 0
    fi
    ast_function_names <<<"${ast}" >"${work_dir}/${config}/${header}.names"
  done
}
export -f windows_header_functions ast_function_names

# Write the names of the functions of Windows 8 or later into a file, one per
# line, sorted: the functions that the mingw-w64 headers of CC declare with
# _WIN32_WINNT=0x0A00 and the newest NTDDI_VERSION of sdkddkver.h, and not with
# _WIN32_WINNT=0x0601 and NTDDI_VERSION=0x06010000 (Windows 7), and the
# exports of WINDOWS8_MSVCRT_EXPORTS. The headers declare these functions under
# _WIN32_WINNT >= 0x0602 or NTDDI_VERSION >= NTDDI_WIN8 and later values. Each
# header of the include directory compiles on its own after windows.h, which a
# precompiled header holds; headers that do not compile as C on their own are
# left out. The list lacks the functions of Windows 8 or later that the headers
# declare without such a guard, for example GetSystemTimePreciseAsFileTime,
# WaitOnAddress, and WakeByAddressSingle in mingw-w64 v14.0.0.
function write_windows8_functions() {
  local output="${1}"
  local work_dir="${2}"
  local include_dir
  include_dir="$(windows_include_dir)" || return
  local macros
  macros="$(printf '#include <sdkddkver.h>\n' | ${CC} -E -dM -x c -)" || return
  local versions
  versions="$(awk '$2 ~ /^NTDDI_WIN[0-9A-Z_]+$/ && $3 ~ /^0x[0-9A-Fa-f]+$/ {print $3}' <<<"${macros}")"
  local newest=0
  local value
  while read -r value; do
    if ((value > newest)); then
      newest="${value}"
    fi
  done <<<"${versions}"
  if ((newest <= 0x06010000)); then
    printf 'ERROR: %s/sdkddkver.h defines no NTDDI version after Windows 7\n' "${include_dir}" >&2
    return 1
  fi

  rm -rf "${work_dir}"
  mkdir -p "${work_dir}/windows7" "${work_dir}/newest" "${work_dir}/skipped"
  printf -- '-U_WIN32_WINNT -D_WIN32_WINNT=0x0601 -DNTDDI_VERSION=0x06010000\n' >"${work_dir}/windows7.defines"
  printf -- '-U_WIN32_WINNT -D_WIN32_WINNT=0x0A00 -DNTDDI_VERSION=0x%08X\n' "${newest}" >"${work_dir}/newest.defines"
  printf '#include <windows.h>\n' >"${work_dir}/pch-windows.h"
  local config
  local defines=()
  local ast
  for config in windows7 newest; do
    read -ra defines <"${work_dir}/${config}.defines"
    # shellcheck disable=SC2086 # CC is a command with arguments
    ${CC} "${defines[@]}" -x c-header "${work_dir}/pch-windows.h" -o "${work_dir}/${config}.pch" || return
    # shellcheck disable=SC2086 # CC is a command with arguments
    ast="$(${CC} "${defines[@]}" -x c -fsyntax-only -fno-color-diagnostics -Xclang -ast-dump "${work_dir}/pch-windows.h")" || return
    ast_function_names <<<"${ast}" >"${work_dir}/${config}/windows.h.names"
  done

  find "${include_dir}" -maxdepth 1 -type f -name '*.h' ! -name 'windows.h' -printf '%f\n' | LC_ALL=C sort >"${work_dir}/headers"
  parallel --will-cite --halt now,fail=1 --jobs="$(nproc)" windows_header_functions "${work_dir}" {} <"${work_dir}/headers" || return

  {
    LC_ALL=C comm -13 \
      <(cat "${work_dir}/windows7/"*.names | LC_ALL=C sort -u) \
      <(cat "${work_dir}/newest/"*.names | LC_ALL=C sort -u)
    printf '%s\n' "${WINDOWS8_MSVCRT_EXPORTS[@]}"
  } | LC_ALL=C sort -u >"${output}"
  local headers
  local skipped
  headers="$(wc -l <"${work_dir}/headers")"
  skipped="$(find "${work_dir}/skipped" -type f | wc -l)"
  printf 'Functions of Windows 8 or later: %s, from %s of the %s headers in %s (NTDDI_VERSION 0x%08X against 0x06010000; %s headers do not compile as C on their own) and %s msvcrt.dll exports\n' \
    "$(wc -l <"${output}")" "$((headers - skipped + 1))" "$((headers + 1))" "${include_dir}" "${newest}" "${skipped}" "${#WINDOWS8_MSVCRT_EXPORTS[@]}"
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
# does, with CONSUMER_CC, check its system dependencies, and run it when
# programs of the target run on the build machine: with the core that OpenBLAS
# detects, and, when the program runs in qemu with the max CPU model, which
# implements every instruction set of the target, with each of the given
# kernel cores, forced through OPENBLAS_CORETYPE. A forced core that leaves the
# detected one in use was not applied. Its reported name may differ from the
# forced one, because OpenBLAS reports the first core that shares the kernel
# table.
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
  local consumer_cc="${CONSUMER_CC:-${CC}}"
  # shellcheck disable=SC2086 # the compiler and the link flags are words
  ${consumer_cc} -O2 -o "${program}" "${CONSUMER_CHECK_SOURCE}" "${lib}" "${flang_rt}" ${link_flags} || return
  check_system_dependencies "${program}" || return

  # The program again with every object of libopenblas.a, so that every
  # function of OpenBLAS links with flang-rt and the system libraries alone.
  local program_all
  program_all="${work_dir}/consumer-check-all$(executable_suffix)"
  local whole_archive=("-Wl,--whole-archive" "${lib}" "-Wl,--no-whole-archive")
  if [[ "${CROSS_TARGET}" == *-apple-darwin ]]; then
    whole_archive=("-Wl,-force_load,${lib}")
  fi
  # shellcheck disable=SC2086 # the compiler and the link flags are words
  ${consumer_cc} -O2 -o "${program_all}" "${CONSUMER_CHECK_SOURCE}" "${whole_archive[@]}" "${flang_rt}" ${link_flags} || return
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
