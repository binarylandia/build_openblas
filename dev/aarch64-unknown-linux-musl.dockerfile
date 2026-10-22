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

# qemu-aarch64 runs the aarch64 check programs. The Debian build is a static
# executable.
RUN set -euxo pipefail >/dev/null \
&& fetch "https://snapshot.debian.org/archive/debian/20260905T205002Z/pool/main/q/qemu/qemu-user_10.0.13%2Bds-0%2Bdeb13u1_amd64.deb" "ca6ede739327a20ae5a3498230c8a3a9a072c586e131bc6bcc1201eb1725e336" /tmp/qemu-user.deb \
&& mkdir /tmp/qemu-user \
&& "${LLVM_DIR}/bin/llvm-ar" x --output=/tmp/qemu-user /tmp/qemu-user.deb data.tar.xz \
&& tar -C /tmp/qemu-user -xJf /tmp/qemu-user/data.tar.xz ./usr/bin/qemu-aarch64 \
&& install -m 0755 /tmp/qemu-user/usr/bin/qemu-aarch64 /usr/local/bin/qemu-aarch64 \
&& rm -rf /tmp/qemu-user /tmp/qemu-user.deb \
&& qemu-aarch64 --version

ENV TRIPLET="aarch64-unknown-linux-musl"
# The GCC cross toolchain of crosstool-NG: the sysroot, crt files, libgcc, and
# libstdc++ headers of the target.
ENV GCC_VERSION="16.2.0"
ENV GCC_DIR="/opt/gcc"
ENV TARGET_TOOLCHAIN_URL="https://github.com/binarylandia/build_crosstool-ng/releases/download/gcc-15.3.0_16.2.0-2026-10-18_08-33-54/gcc-16.2.0-aarch64-unknown-linux-musl-2026-10-18_08-33-54.tar.xz"
ENV TARGET_TOOLCHAIN_SHA256="528cad5408025a62e09ee601a4888a4a2c519134c937c9b89a3008f6a5e8a441"
RUN set -euxo pipefail >/dev/null \
&& mkdir -p "${GCC_DIR}" \
&& fetch "${TARGET_TOOLCHAIN_URL}" "${TARGET_TOOLCHAIN_SHA256}" /tmp/download \
&& tar -C "${GCC_DIR}" -xJf /tmp/download \
&& rm /tmp/download \
&& ${GCC_DIR}/bin/${TRIPLET}-gcc -v

# The CPU baseline of the programs that link the archives: Armv8.0, with atomic
# operations through the outline atomics helpers, which use the LSE
# instructions when the CPU has them.
# The C and Fortran code of OpenBLAS and flang-rt compile with these flags.
# OpenBLAS adds CPU flags after them (Makefile.<arch>) for the kernels that it
# selects at run time, and on aarch64 also for its target CPU.
ENV TARGET_CPU_FLAGS="-march=armv8-a -moutline-atomics"

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
# qemu-aarch64 runs the programs of the target with the dynamic loader and the
# libraries of the sysroot, on a CPU with every aarch64 extension that OpenBLAS
# has kernels for (SVE, SME). Both variables also apply to the binfmt_misc
# handler of the build machine, which runs the OpenBLAS tests.
ENV QEMU_LD_PREFIX="${GCC_DIR}/${TRIPLET}/sysroot"
ENV QEMU_CPU="max"
ENV TARGET_RUNNER="qemu-aarch64"


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
