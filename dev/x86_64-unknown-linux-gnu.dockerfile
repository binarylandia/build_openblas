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

# clang, flang, lld, and the LLVM binary tools. The runtimes of the target are
# built below from the LLVM source of this release.
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

ENV TRIPLET="x86_64-unknown-linux-gnu"
# The GCC cross toolchain of crosstool-NG: the sysroot, crt files, libgcc, and
# libstdc++ headers of the target.
ENV GCC_VERSION="16.2.0"
ENV GCC_DIR="/opt/gcc"
ENV TARGET_TOOLCHAIN_URL="https://github.com/binarylandia/build_crosstool-ng/releases/download/gcc-15.3.0_16.2.0-2026-10-18_08-33-54/gcc-16.2.0-x86_64-unknown-linux-gnu-2026-10-18_08-33-54.tar.xz"
ENV TARGET_TOOLCHAIN_SHA256="db20b5651bc60966e834be43ada16ef361afbc8686025f8d3def5404ccac9ea3"
RUN set -euxo pipefail >/dev/null \
&& mkdir -p "${GCC_DIR}" \
&& fetch "${TARGET_TOOLCHAIN_URL}" "${TARGET_TOOLCHAIN_SHA256}" /tmp/download \
&& tar -C "${GCC_DIR}" -xJf /tmp/download \
&& rm /tmp/download \
&& ${GCC_DIR}/bin/${TRIPLET}-gcc -v

# The CPU baseline of the programs that link the archives: x86-64-v2 (SSE4.2,
# POPCNT, CMPXCHG16B; Intel Nehalem, AMD Bulldozer, or newer).
# The C and Fortran code of OpenBLAS and flang-rt compile with these flags.
# OpenBLAS adds CPU flags after them (Makefile.<arch>) for the kernels that it
# selects at run time, and on aarch64 also for its target CPU.
ENV TARGET_CPU_FLAGS="-march=x86-64-v2"

# clang and flang for the target: --target=<triple> loads <triple>.cfg from the
# bin directory of LLVM, which selects the sysroot and the GCC runtime (crt
# files, libgcc, libstdc++ headers) of the crosstool-NG toolchain, and lld.
COPY docker/files/build-llvm-runtimes /usr/local/bin/build-llvm-runtimes
COPY patches /usr/local/share/build-llvm-runtimes/patches
RUN set -euxo pipefail >/dev/null \
&& printf -- '%s\n' \
  "--sysroot=${GCC_DIR}/${TRIPLET}/sysroot" \
  "--gcc-install-dir=${GCC_DIR}/lib/gcc/${TRIPLET}/${GCC_VERSION}" \
  "-fuse-ld=lld" \
  >"${LLVM_DIR}/bin/${TRIPLET}.cfg" \
&& fetch "${LLVM_SOURCE}" "${LLVM_SOURCE_SHA256}" "/tmp/${LLVM_SOURCE##*/}" \
&& build-llvm-runtimes "/tmp/${LLVM_SOURCE##*/}" "${TRIPLET}" \
&& rm "/tmp/${LLVM_SOURCE##*/}" \
&& ls "${LLVM_DIR}/lib/clang/22/lib/${TRIPLET}/libflang_rt.runtime.a" "${LLVM_DIR}/lib/clang/22/lib/${TRIPLET}/libclang_rt.builtins.a"

ENV HOSTCC="${LLVM_DIR}/bin/clang --no-default-config"
ENV CC="${LLVM_DIR}/bin/clang --target=${TRIPLET}"
ENV CXX="${LLVM_DIR}/bin/clang++ --target=${TRIPLET}"
ENV FC="${LLVM_DIR}/bin/flang --target=${TRIPLET}"
ENV AR="${LLVM_DIR}/bin/llvm-ar"
ENV LD="${LLVM_DIR}/bin/ld.lld"
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
