#!/usr/bin/env bash
#
# Helpers shared by scripts/main and scripts/main-wasm.
#

export NICE="nice -19 ionice -c2 -n5"

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

# Write <archive>.json next to an archive: the given key-value pairs and the
# build provenance that ./build passes in. scripts/release puts these files into
# the manifest of a release.
function write_metadata() {
  local archive="${1}"
  shift
  local named=()
  while (($# > 0)); do
    named+=(--arg "${1}" "${2}")
    shift 2
  done
  local file="${archive##*/}"
  jq -n "${named[@]}" \
    --arg name "${file%.tar.xz}" \
    --arg target "${CROSS_TARGET:?}" \
    --arg dockerfile "dev/${CROSS_TARGET}.dockerfile" \
    --arg dockerfile_sha256 "${DOCKERFILE_SHA256:?}" \
    --arg build_commit "${BUILD_COMMIT:?}" \
    --arg build_dirty "${BUILD_DIRTY:?}" \
    --arg build_time "${build_time:?}" \
    --arg file "${file}" \
    '$ARGS.named | .build_dirty = (.build_dirty == "true") | .files = [.file] | del(.file)' \
    >"${archive%.tar.xz}.json"
}
