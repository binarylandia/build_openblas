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

function abspath() {
  readlink -m "$1"
}

function log() {
  tee -a "${1}" | stdbuf -oL grep --color=always -iE "error|fail|cannot|can't|unable|"
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

# Write <archive>.json next to an archive: the fields of a JSON object and the
# build provenance that ./build passes in. scripts/release puts these files into
# the manifest of a release.
function write_metadata() {
  local archive="${1}"
  local fields="${2}"
  local file="${archive##*/}"
  jq -n \
    --argjson fields "${fields}" \
    --arg name "${file%.tar.xz}" \
    --arg target "${CROSS_TARGET:?}" \
    --arg dockerfile "dev/${CROSS_TARGET}.dockerfile" \
    --arg dockerfile_sha256 "${DOCKERFILE_SHA256:?}" \
    --arg build_commit "${BUILD_COMMIT:?}" \
    --arg build_dirty "${BUILD_DIRTY:?}" \
    --arg build_time "${build_time:?}" \
    --arg file "${file}" \
    '$fields + {
      name: $name,
      target: $target,
      dockerfile: $dockerfile,
      dockerfile_sha256: $dockerfile_sha256,
      build_commit: $build_commit,
      build_dirty: ($build_dirty == "true"),
      build_time: $build_time,
      files: [$file]
    }' \
    >"${archive%.tar.xz}.json"
}
