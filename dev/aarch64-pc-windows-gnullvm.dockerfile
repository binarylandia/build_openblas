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

# clang, flang, lld, and the LLVM binary tools. The Fortran runtime of the
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

# llvm-mingw: the static UCRT sysroot of the target, compiler-rt, and the
# <triple>-clang wrappers, which load the configuration <triple>.cfg from the
# bin directory of LLVM (sysroot, compiler-rt, libc++, libunwind, lld). The
# archive unpacks into the LLVM installation of the same release.
ENV TRIPLET="aarch64-w64-mingw32"
ENV TARGET_TOOLCHAIN_URL="https://github.com/binarylandia/build_llvm/releases/download/${LLVM_RELEASE}/llvm-mingw-22.1.8-2026-10-18_10-26-24.tar.zst"
ENV TARGET_TOOLCHAIN_SHA256="4cd60450e4dc43766e1302cd4c2beb345ace65f36d7204b0aac068d744778e85"
RUN set -euxo pipefail >/dev/null \
&& fetch "${TARGET_TOOLCHAIN_URL}" "${TARGET_TOOLCHAIN_SHA256}" /tmp/download \
&& zstd -dc /tmp/download | tar -C "${LLVM_DIR}" -x \
&& rm /tmp/download \
&& ls "${LLVM_DIR}/lib/clang/22/lib/windows/libclang_rt.builtins-aarch64.a" \
&& "${LLVM_DIR}/bin/${TRIPLET}-clang" --version

# The CPU baseline of the programs that link the archives: Armv8.0 with the LSE
# atomics of Armv8.1, which Windows 11 on Arm requires.
# The C and Fortran code of OpenBLAS and flang-rt compile with these flags.
# OpenBLAS adds CPU flags after them (Makefile.<arch>) for the kernels that it
# selects at run time, and on aarch64 also for its target CPU.
ENV TARGET_CPU_FLAGS="-march=armv8-a+lse"

# flang for the target: --target=<triple> loads <normalized triple>-flang.cfg
# (for example x86_64-w64-windows-gnu-flang.cfg), which names the sysroot,
# compiler-rt, and lld, instead of the configuration of clang, whose C++
# runtime options (-stdlib, -unwindlib) flang rejects.
COPY docker/files/build-llvm-runtimes /usr/local/bin/build-llvm-runtimes
COPY patches /usr/local/share/build-llvm-runtimes/patches
RUN set -euxo pipefail >/dev/null \
&& printf -- '%s\n' \
  "--sysroot=<CFGDIR>/../${TRIPLET}" \
  "-rtlib=compiler-rt" \
  "-fuse-ld=lld" \
  >"${LLVM_DIR}/bin/$("${LLVM_DIR}/bin/clang" --target="${TRIPLET}" -print-target-triple)-flang.cfg" \
&& fetch "${LLVM_SOURCE}" "${LLVM_SOURCE_SHA256}" "/tmp/${LLVM_SOURCE##*/}" \
&& build-llvm-runtimes "/tmp/${LLVM_SOURCE##*/}" "${TRIPLET}" \
&& rm "/tmp/${LLVM_SOURCE##*/}" \
&& ls "${LLVM_DIR}/lib/clang/22/lib/aarch64-w64-windows-gnu/libflang_rt.runtime.a"

ENV HOSTCC="${LLVM_DIR}/bin/clang --no-default-config"
ENV CC="${LLVM_DIR}/bin/${TRIPLET}-clang"
ENV CXX="${LLVM_DIR}/bin/${TRIPLET}-clang++"
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
ENV TARGET_NO_RUN="aarch64 Windows programs do not run on the x86_64 Linux build machine"


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
