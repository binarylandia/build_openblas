FROM quay.io/pypa/manylinux2014_x86_64:2024.10.19-1@sha256:2d03fb51340fbbc5732c7251eedc2ac015c96a16ed91f818ea500e5b2099da96

SHELL ["bash", "-euxo", "pipefail", "-c"]

COPY docker/files/fetch /usr/local/bin/fetch

RUN set -euxo pipefail >/dev/null \
&& sed -i "s/enabled=1/enabled=0/g" "/etc/yum/pluginconf.d/fastestmirror.conf" \
&& sed -i "s/enabled=1/enabled=0/g" "/etc/yum/pluginconf.d/ovl.conf" \
&& yum clean all >/dev/null \
&& yum install -y epel-release >/dev/null \
&& yum remove -y \
  clang* \
  devtoolset* \
  gcc* \
  llvm-toolset* \
>/dev/null \
&& yum install -y \
  bash \
  ca-certificates \
  curl \
  git \
  jq \
  make \
  parallel \
  patch \
  pkgconfig \
  sudo \
  tar \
  xz \
  zstd \
>/dev/null \
&& yum clean all >/dev/null \
&& rm -rf /var/cache/yum

ENV CCACHE_DIR="/cache/ccache"
ENV CCACHE_NOCOMPRESS="1"
ENV CCACHE_MAXSIZE="50G"
RUN set -euxo pipefail >/dev/null \
&& fetch "https://github.com/ccache/ccache/releases/download/v4.10.2/ccache-4.10.2-linux-x86_64.tar.xz" "80cab87bd510eca796467aee8e663c398239e0df1c4800a0b5dff11dca0b4f18" /tmp/download \
&& tar --strip-components=1 -C "/usr/bin" -xJf /tmp/download "ccache-4.10.2-linux-x86_64/ccache" \
&& rm /tmp/download \
&& which ccache \
&& ccache --version

RUN set -euxo pipefail >/dev/null \
&& fetch "https://github.com/binarylandia/build_gcc/releases/download/2024-11-03_12-57-14/gcc-14.2.0-host-x86_64-unknown-linux-gnu.2.17-2024-11-03_12-57-14.tar.xz" "7695cb4c68fa2e703bca4d0e5ea7bce3f6fc8ac2db507279d02818e3bd704bcc" /tmp/download \
&& tar -C "/usr" -xJf /tmp/download \
&& rm /tmp/download \
&& ls /usr/bin/gcc \
&& gcc -v \
&& ls /usr/bin/gcc-ar \
&& gcc-ar --version

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
ENV TRIPLET="x86_64-apple-darwin20.2"
ENV MACOSX_DEPLOYMENT_TARGET="10.12"
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

# The CPU baseline of the programs that link the archives: x86-64-v2 (SSE4.2,
# POPCNT, CMPXCHG16B; Intel Nehalem, AMD Bulldozer, or newer).
# The C and Fortran code of OpenBLAS and flang-rt compile with these flags.
# OpenBLAS adds CPU flags after them (Makefile.<arch>) for the kernels that it
# selects at run time, and on aarch64 also for its target CPU.
ENV TARGET_CPU_FLAGS="-march=x86-64-v2"

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
