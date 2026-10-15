# syntax=docker/dockerfile:1
# check=experimental=all
#
# Build image of the wasm32-unknown-emscripten target. Emscripten compiles
# OpenBLAS, a native GCC compiles the helper programs that the OpenBLAS build
# runs on the build machine, and Node runs emcc and the link checks.
FROM debian:12.14-slim@sha256:60eac759739651111db372c07be67863818726f754804b8707c90979bda511df

SHELL ["bash", "-euxo", "pipefail", "-c"]

RUN set -euxo pipefail >/dev/null \
&& export DEBIAN_FRONTEND=noninteractive \
&& apt-get update -qq \
&& apt-get install --no-install-recommends --yes -qq \
  bash \
  ca-certificates \
  curl \
  file \
  gcc \
  libc6-dev \
  make \
  patch \
  python3 \
  sudo \
  xz-utils \
>/dev/null \
&& apt-get clean autoclean >/dev/null \
&& apt-get autoremove --yes >/dev/null \
&& rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

ARG NODE_VERSION="24.21.0"
ARG NODE_SHA256="fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6"
ARG NODE_DIR="/opt/node"
RUN set -euxo pipefail >/dev/null \
&& curl -fsSLo "/tmp/node.tar.xz" "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
&& printf '%s  %s\n' "${NODE_SHA256}" "/tmp/node.tar.xz" | sha256sum --check --quiet \
&& mkdir -p "${NODE_DIR}" \
&& tar -xJf "/tmp/node.tar.xz" --strip-components=1 -C "${NODE_DIR}" \
&& rm "/tmp/node.tar.xz" \
&& ln -s "${NODE_DIR}/bin/node" "/usr/local/bin/node" \
&& node --version

ARG EMSCRIPTEN_VERSION="6.0.10"
ARG EMSCRIPTEN_BUILD="666337b525e673e769121856d175f6f52b8ead64"
ARG EMSCRIPTEN_SHA256="a51dd2829bdf725d268974728e032533b106ea01cb482a62288ec12627a7abbe"
ARG EMSCRIPTEN_DIR="/opt/emscripten"

# Emscripten: the archive that `emsdk install <version>` downloads; the build id
# is the entry of the version in emscripten-releases-tags.json of emsdk. The
# configuration names the LLVM and Binaryen of the archive. Only the emcc front
# end goes on PATH. The cache holds the prebuilt system libraries and stays
# writable for its lock and sanity files, because the container runs as the
# host user.
ENV PATH="${EMSCRIPTEN_DIR}/emscripten:${PATH}"
RUN set -euxo pipefail >/dev/null \
&& curl -fsSLo "/tmp/wasm-binaries.tar.xz" "https://storage.googleapis.com/webassembly/emscripten-releases-builds/linux/${EMSCRIPTEN_BUILD}/wasm-binaries.tar.xz" \
&& printf '%s  %s\n' "${EMSCRIPTEN_SHA256}" "/tmp/wasm-binaries.tar.xz" | sha256sum --check --quiet \
&& mkdir -p "${EMSCRIPTEN_DIR}" \
&& tar -xJf "/tmp/wasm-binaries.tar.xz" --strip-components=1 -C "${EMSCRIPTEN_DIR}" \
&& rm "/tmp/wasm-binaries.tar.xz" \
&& printf "LLVM_ROOT = '%s/bin'\nBINARYEN_ROOT = '%s'\n" "${EMSCRIPTEN_DIR}" "${EMSCRIPTEN_DIR}" >"${EMSCRIPTEN_DIR}/emscripten/.emscripten" \
&& grep -qxF "${EMSCRIPTEN_VERSION}-git" "${EMSCRIPTEN_DIR}/emscripten/emscripten-version.txt" \
&& emcc --version \
&& chmod -R a+rwX "${EMSCRIPTEN_DIR}/emscripten/cache"

ARG USER=user
ARG GROUP=user
ARG UID
ARG GID

ENV USER=$USER
ENV GROUP=$GROUP
ENV UID=$UID
ENV GID=$GID
ENV TERM="xterm-256color"
ENV HOME="/home/${USER}"

COPY docker/files /

RUN set -euxo pipefail >/dev/null \
&& /create-user \
&& touch "${HOME}/.hushlogin" \
&& chown -R "${UID}:${GID}" "${HOME}"

USER ${USER}
