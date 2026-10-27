#!/usr/bin/env bash
#
# Helpers shared by scripts/main and scripts/main-wasm.
#
# shellcheck shell=bash disable=SC2034 # the sourcing scripts use the constants

export NICE="nice -19 ionice -c2 -n5"

# The OpenBLAS source of every target: a develop commit after 0.3.34. Its C
# LAPACK functions and XERBLA take no hidden string lengths and return void, as
# Rust's lapack-sys declares them (OpenMathLib/OpenBLAS#6017 and #6082), which
# WebAssembly needs because it traps on a call whose signature differs from the
# callee. It also has the fixes for the dgemm stack overflow on AMD Zen 4 and
# Zen 5 servers (OpenMathLib/OpenBLAS#6013) that 0.3.34 lacks.
# OPENBLAS_COMMITS_AFTER_TAG counts the commits of the commit after the tag, so
# OPENBLAS_VERSION reads like `git describe` (the develop branch still carries
# the version string of the last release with a .dev suffix).
OPENBLAS_COMMIT="de5d4914c558cf36cf67ee25ba78870e0e239265"
OPENBLAS_BASE_TAG="v0.3.34"
OPENBLAS_COMMITS_AFTER_TAG="432"
OPENBLAS_SOURCE_URL="https://github.com/OpenMathLib/OpenBLAS/archive/${OPENBLAS_COMMIT}.tar.gz"
OPENBLAS_SOURCE_SHA256="f3158e302ce82a0e813db977441ce03987dc0e6c4b3e6e30b5701aa4a10e8ecd"
OPENBLAS_VERSION="${OPENBLAS_BASE_TAG#v}-${OPENBLAS_COMMITS_AFTER_TAG}-g${OPENBLAS_COMMIT:0:8}"

# The build record inside each archive (see package_with_record).
BUILD_RECORD="share/build_openblas/build.json"

function abspath() {
  readlink -m "$1"
}

function log() {
  # grep exits 1 when the command prints nothing, which is no failure.
  tee -a "${1}" | { stdbuf -oL grep --color=always -iE "error|fail|cannot|can't|unable|" || (($? == 1)); }
}

# Write a directory as an xz-compressed tar archive. The entries are sorted,
# owned by root, and carry the time SOURCE_DATE_EPOCH, and xz runs in its
# multi-threaded mode, whose output does not depend on the thread count, so the
# same files always give the same archive.
function package() {
  local input_dir="${1}"
  local output_tarball="${2}"
  local threads
  threads="$(nproc)"
  ((threads > 1)) || threads=2
  mkdir -p "$(dirname "${output_tarball}")"
  find "${input_dir}" -mindepth 1 -printf "%P\n" | LC_ALL=C sort |
    ${NICE} tar --posix --no-recursion --mtime="@${SOURCE_DATE_EPOCH:?}" --owner=0 --group=0 --numeric-owner \
      --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
      -cf - -C "${input_dir}" --files-from=- |
    ${NICE} xz -T"${threads}" >"${output_tarball}"
}

# Download a source tarball once, check its sha256, and unpack it into a new
# directory.
function fetch_source() {
  local url="${1}"
  local sha256="${2}"
  local tarball="${3}"
  local src_dir="${4}"
  if [[ ! -f "${tarball}" ]]; then
    mkdir -p "$(dirname "${tarball}")"
    curl -fsSLo "${tarball}.part" --retry 3 "${url}"
    mv "${tarball}.part" "${tarball}"
  fi
  local actual
  actual="$(sha256sum "${tarball}" | cut -d' ' -f1)"
  if [[ "${actual}" != "${sha256}" ]]; then
    rm -f "${tarball}"
    printf 'ERROR: checksum mismatch for %s: expected %s, got %s\n' "${url}" "${sha256}" "${actual}" >&2
    return 1
  fi
  rm -rf "${src_dir}"
  mkdir -p "${src_dir}"
  tar -xzf "${tarball}" -C "${src_dir}" --strip-components=1
}

# Make the pkg-config file of an installation relocatable: OpenBLAS writes the
# installation prefix of the build into libdir and includedir, which do not
# exist where a consumer unpacks the archive. Both name folders relative to the
# file (${pcfiledir}) instead, so the unpacked archive works in any folder.
function relocate_pkg_config() {
  local install_dir="${1}"
  local pc="${install_dir}/lib/pkgconfig/openblas.pc"
  if ! grep -q '^libdir=' "${pc}" || ! grep -q '^includedir=' "${pc}"; then
    printf 'ERROR: %s has no libdir= or no includedir= line; update relocate_pkg_config for this OpenBLAS version.\n' "${pc}" >&2
    return 1
  fi
  # shellcheck disable=SC2016 # pkg-config expands ${pcfiledir}
  sed -i \
    -e 's|^libdir=.*$|libdir=${pcfiledir}/..|' \
    -e 's|^includedir=.*$|includedir=${pcfiledir}/../../include|' \
    "${pc}"
}

# Fail unless pkg-config, with the pkg-config file of an installation as its
# only search folder, names the library and header folders of the installation
# and each given library flag (-lopenblas). pkg-config prints the folders
# relative to the file (lib/pkgconfig/..), so they are compared after
# resolution.
function check_pkg_config() {
  local install_dir="${1}"
  shift
  local pc_dir="${install_dir}/lib/pkgconfig"
  local libs
  local cflags
  libs="$(PKG_CONFIG_PATH="" PKG_CONFIG_LIBDIR="${pc_dir}" pkg-config --libs openblas)" || return
  cflags="$(PKG_CONFIG_PATH="" PKG_CONFIG_LIBDIR="${pc_dir}" pkg-config --cflags openblas)" || return
  local lib_dir
  local include_dir
  lib_dir="$(realpath "${install_dir}/lib")" || return
  include_dir="$(realpath "${install_dir}/include")" || return
  local words=()
  read -ra words <<<"${libs} ${cflags}"
  local word
  local found_lib_dir=false
  local found_include_dir=false
  for word in "${words[@]}"; do
    if [[ "${word}" == -L* && "$(realpath -m "${word#-L}")" == "${lib_dir}" ]]; then
      found_lib_dir=true
    elif [[ "${word}" == -I* && "$(realpath -m "${word#-I}")" == "${include_dir}" ]]; then
      found_include_dir=true
    fi
  done
  local missing=()
  "${found_lib_dir}" || missing+=("-L${lib_dir}")
  "${found_include_dir}" || missing+=("-I${include_dir}")
  local flag
  for flag in "$@"; do
    [[ " ${libs} " == *" ${flag} "* ]] || missing+=("${flag}")
  done
  if ((${#missing[@]} > 0)); then
    printf 'ERROR: pkg-config prints "%s" and "%s" for %s, without: %s\n' "${libs}" "${cflags}" "${pc_dir}/openblas.pc" "${missing[*]}" >&2
    return 1
  fi
}

# Package an installation into an archive with its build record, and write the
# record next to the archive as <archive>.json, which scripts/release puts into
# the manifest of a release. The record holds the fields of a JSON object, the
# files of the archive (contents), and the build provenance that ./build passes
# in; the archive holds it as share/build_openblas/build.json.
function package_with_record() {
  local install_dir="${1}"
  local archive="${2}"
  local fields="${3}"
  local contents
  contents="$(archive_contents "${install_dir}")" || return
  local record
  record="$(archive_record "${archive}" "${fields}" "${contents}")" || return
  mkdir -p "$(dirname "${install_dir}/${BUILD_RECORD}")"
  printf '%s\n' "${record}" >"${install_dir}/${BUILD_RECORD}"
  package "${install_dir}" "${archive}" || return
  check_archive_contents "${archive}" "${record}" || return
  printf '%s\n' "${record}" >"${archive%.tar.xz}.json"
}

# Print the files of an installation, with the build record that
# package_with_record adds, as a sorted JSON array.
function archive_contents() {
  local install_dir="${1}"
  local files
  files="$(find "${install_dir}" -type f -printf '%P\n')" || {
    printf 'ERROR: cannot list the files of %s\n' "${install_dir}" >&2
    return 1
  }
  printf '%s\n' ${files:+"${files}"} "${BUILD_RECORD}" | LC_ALL=C sort -u | jq -R . | jq -s .
}

# Print the build record of an archive as JSON.
function archive_record() {
  local archive="${1}"
  local fields="${2}"
  local contents="${3}"
  local file="${archive##*/}"
  jq -n \
    --argjson fields "${fields}" \
    --argjson contents "${contents}" \
    --arg name "${file%.tar.xz}" \
    --arg target "${CROSS_TARGET:?}" \
    --arg dockerfile "dev/${CROSS_TARGET}.dockerfile" \
    --arg dockerfile_sha256 "${DOCKERFILE_SHA256:?}" \
    --arg build_commit "${BUILD_COMMIT:?}" \
    --arg build_dirty "${BUILD_DIRTY:?}" \
    --arg build_time "${build_time:?}" \
    --arg file "${file}" \
    '$fields + {
      contents: $contents,
      name: $name,
      target: $target,
      dockerfile: $dockerfile,
      dockerfile_sha256: $dockerfile_sha256,
      build_commit: $build_commit,
      build_dirty: ($build_dirty == "true"),
      build_time: $build_time,
      files: [$file]
    }'
}

# Fail unless the files of an archive are the contents of its build record.
function check_archive_contents() {
  local archive="${1}"
  local record="${2}"
  local listed
  local expected
  listed="$(tar -tJf "${archive}" | sed '/\/$/d' | LC_ALL=C sort)" || return
  expected="$(jq -r '.contents[]' <<<"${record}")" || return
  if [[ "${listed}" != "${expected}" ]]; then
    printf 'ERROR: the files of %s differ from the contents of its build record:\n%s\n' "${archive}" \
      "$(diff <(printf '%s\n' "${expected}") <(printf '%s\n' "${listed}"))" >&2
    return 1
  fi
}
