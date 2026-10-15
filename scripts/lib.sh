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

function package() {
  local input_dir="${1}"
  local output_tarball="${2}"
  mkdir -p "$(dirname "${output_tarball}")"
  ${NICE} find "${input_dir}" -printf "%P\n" |
    ${NICE} tar --no-recursion -cf - -C "${input_dir}" --files-from=- |
    ${NICE} xz -T0 -k >"${output_tarball}"
}
