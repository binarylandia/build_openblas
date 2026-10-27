# syntax=docker/dockerfile:1
# check=experimental=all
#
# Build image of the wasm32-unknown-emscripten target. Emscripten compiles
# OpenBLAS, a native GCC compiles the helper programs that the OpenBLAS build
# runs on the build machine, and Node runs emcc and the link checks.
FROM debian:13.7-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad

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
  jq \
  libc6-dev \
  make \
  patch \
  pkg-config \
  python3 \
  sudo \
  xz-utils \
>/dev/null \
&& apt-get clean autoclean >/dev/null \
&& apt-get autoremove --yes >/dev/null \
&& rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

COPY --link "docker/files/distrust-compromised-roots" "/"
RUN /distrust-compromised-roots

ARG NODE_VERSION="24.22.1"
ARG NODE_SHA256="6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6"
ARG NODE_DIR="/opt/node"
RUN set -euxo pipefail >/dev/null \
&& curl -fsSLo "/tmp/node.tar.xz" "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
&& printf '%s  %s\n' "${NODE_SHA256}" "/tmp/node.tar.xz" | sha256sum --check --quiet \
&& mkdir -p "${NODE_DIR}" \
&& tar -xJf "/tmp/node.tar.xz" --strip-components=1 -C "${NODE_DIR}" \
&& rm "/tmp/node.tar.xz" \
&& ln -s "${NODE_DIR}/bin/node" "/usr/local/bin/node" \
&& node --version

ARG EMSCRIPTEN_VERSION="6.0.13"
ARG EMSCRIPTEN_BUILD="eb132757325583b787fe9414b09afea9442b72ad"
ARG EMSCRIPTEN_SHA256="cda6801012ff3319a539111826ed02a9abd7eff135c2ef261c8941caf5a3763e"
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
