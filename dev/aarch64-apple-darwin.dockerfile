FROM debian:13.7-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad

SHELL ["bash", "-euxo", "pipefail", "-c"]

COPY docker/files/fetch /usr/local/bin/fetch

RUN set -euxo pipefail >/dev/null \
&& export DEBIAN_FRONTEND=noninteractive \
&& apt-get update -qq \
&& apt-get install --no-install-recommends --yes -qq \
  bash \
  ca-certificates \
  ccache \
  curl \
  g++ \
  gcc \
  git \
  jq \
  make \
  parallel \
  patch \
  pkg-config \
  sudo \
  tar \
  xz-utils \
  zstd \
>/dev/null \
&& apt-get clean autoclean >/dev/null \
&& apt-get autoremove --yes >/dev/null \
&& rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

COPY --link "docker/files/distrust-compromised-roots" "/"
RUN /distrust-compromised-roots

ENV CCACHE_DIR="/cache/ccache"
ENV CCACHE_NOCOMPRESS="1"
ENV CCACHE_MAXSIZE="50G"

# clang, flang, ld64.lld, and the LLVM binary tools. The Fortran runtime of the
# target is built below from the LLVM source of this release.
ENV LLVM_RELEASE="llvm-22.1.8-2026-10-18_10-26-24"
ENV LLVM_SOURCE="https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/llvm-project-22.1.8.src.tar.xz"
ENV LLVM_SOURCE_SHA256="922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888"
ENV LLVM_DIR="/opt/llvm"
RUN set -euxo pipefail >/dev/null \
&& mkdir -p "${LLVM_DIR}" \
&& fetch "https://github.com/binarylandia/build_llvm/releases/download/${LLVM_RELEASE}/${LLVM_RELEASE}.tar.zst" "c80ac102a9b833ccc3de6e838fba592f76334bda8b57b6629f853d8d2a84bae8" /tmp/download \
&& zstd -dc /tmp/download | tar -C "${LLVM_DIR}" -x \
&& rm /tmp/download \
&& "${LLVM_DIR}/bin/clang" --version \
&& "${LLVM_DIR}/bin/flang" --version

# osxcross: the macOS SDK, compiler wrappers that run the clang and ld64.lld of
# LLVM_DIR from PATH with the SDK and the deployment target, and compiler-rt for
# macOS in the layout of the clang resource directory.
ENV TRIPLET="arm64-apple-darwin20.2"
ENV MACOSX_DEPLOYMENT_TARGET="11.0"
ENV OSXCROSS_DIR="/opt/osxcross"
ENV SDKROOT="${OSXCROSS_DIR}/SDK/MacOSX11.1.sdk"
ENV TARGET_TOOLCHAIN_URL="https://github.com/binarylandia/build_osxcross/releases/download/osxcross-27d21e4-sdk11.1-2026-10-18_09-15-29/osxcross-27d21e4-2026-10-18_09-15-29.tar.zst"
ENV TARGET_TOOLCHAIN_SHA256="3013322802c7e765dc1320f4f97ea952673f6e2efbe12b1b7a4c0ec75aff03db"
ENV PATH="${OSXCROSS_DIR}/bin:${LLVM_DIR}/bin:${PATH}"
RUN set -euxo pipefail >/dev/null \
&& mkdir -p "${OSXCROSS_DIR}" \
&& fetch "${TARGET_TOOLCHAIN_URL}" "${TARGET_TOOLCHAIN_SHA256}" /tmp/download \
&& zstd -dc /tmp/download | tar -C "${OSXCROSS_DIR}" -x \
&& rm /tmp/download \
&& cp -r "${OSXCROSS_DIR}/compiler-rt/." "$("${LLVM_DIR}/bin/clang" -print-resource-dir)/" \
&& ls "${SDKROOT}/usr/lib/libSystem.B.tbd" \
&& "${TRIPLET}-clang" --version

# The CPU baseline of the programs that link the archives: Apple M1.
# The C and Fortran code of OpenBLAS and flang-rt compile with these flags.
# OpenBLAS adds CPU flags after them (Makefile.<arch>) for the kernels that it
# selects at run time, and on aarch64 also for its target CPU.
ENV TARGET_CPU_FLAGS="-mcpu=apple-m1"

# flang for the target: --target=<triple> loads <triple>-flang.cfg from the bin
# directory of LLVM, which names the SDK, the deployment target, and ld64.lld,
# the flags that the osxcross wrappers add for clang.
COPY docker/files/build-llvm-runtimes /usr/local/bin/build-llvm-runtimes
COPY patches /usr/local/share/build-llvm-runtimes/patches
RUN set -euxo pipefail >/dev/null \
&& printf -- '%s\n' \
  "-isysroot ${SDKROOT}" \
  "-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}" \
  "-fuse-ld=lld" \
  >"${LLVM_DIR}/bin/${TRIPLET}-flang.cfg" \
&& fetch "${LLVM_SOURCE}" "${LLVM_SOURCE_SHA256}" "/tmp/${LLVM_SOURCE##*/}" \
&& build-llvm-runtimes "/tmp/${LLVM_SOURCE##*/}" "${TRIPLET}" \
&& rm "/tmp/${LLVM_SOURCE##*/}" \
&& ls "${LLVM_DIR}/lib/clang/22/lib/darwin/libflang_rt.runtime.a" "${LLVM_DIR}/lib/clang/22/lib/darwin/libclang_rt.osx.a"

ENV HOSTCC="${LLVM_DIR}/bin/clang --no-default-config"
ENV CC="${OSXCROSS_DIR}/bin/${TRIPLET}-clang"
ENV CXX="${OSXCROSS_DIR}/bin/${TRIPLET}-clang++"
ENV FC="${LLVM_DIR}/bin/flang --target=${TRIPLET}"
ENV AR="${LLVM_DIR}/bin/llvm-ar"
ENV LD="${LLVM_DIR}/bin/ld64.lld"
ENV NM="${LLVM_DIR}/bin/llvm-nm"
ENV OBJCOPY="${LLVM_DIR}/bin/llvm-objcopy"
ENV OBJDUMP="${LLVM_DIR}/bin/llvm-objdump"
ENV RANLIB="${LLVM_DIR}/bin/llvm-ranlib"
ENV READELF="${LLVM_DIR}/bin/llvm-readelf"
ENV READOBJ="${LLVM_DIR}/bin/llvm-readobj"
ENV SIZE="${LLVM_DIR}/bin/llvm-size"
ENV STRINGS="${LLVM_DIR}/bin/llvm-strings"
ENV STRIP="${LLVM_DIR}/bin/llvm-strip"
ENV TARGET_RUNNER=""
ENV TARGET_NO_RUN="macOS programs do not run on the Linux build machine"


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
&& sed -i /etc/sudoers -re 's/^%sudo.*/%sudo ALL=(ALL:ALL) NOPASSWD: ALL/g' \
&& sed -i /etc/sudoers -re 's/^root.*/root ALL=(ALL:ALL) NOPASSWD: ALL/g' \
&& sed -i /etc/sudoers -re 's/^#includedir.*/## **Removed the include directive** ##"/g' \
&& echo "%sudo ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
&& echo "${USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
&& touch ${HOME}/.hushlogin \
&& chown -R ${UID}:${GID} "${HOME}"

USER ${USER}
