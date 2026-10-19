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

# Wine runs the check programs and the OpenBLAS tests of the target, in the
# prefix ~/.wine, which it creates on the first run.
RUN set -euxo pipefail >/dev/null \
&& yum install -y wine-core >/dev/null \
&& yum clean all >/dev/null \
&& rm -rf /var/cache/yum \
&& wine64 --version

# llvm-mingw: the static UCRT sysroot of the target, compiler-rt, and the
# <triple>-clang wrappers, which load the configuration <triple>.cfg from the
# bin directory of LLVM (sysroot, compiler-rt, libc++, libunwind, lld). The
# archive unpacks into the LLVM installation of the same release.
ENV TRIPLET="x86_64-w64-mingw32"
ENV TARGET_TOOLCHAIN_URL="https://github.com/binarylandia/build_llvm/releases/download/${LLVM_RELEASE}/llvm-mingw-22.1.8-2026-10-18_10-26-24.tar.zst"
ENV TARGET_TOOLCHAIN_SHA256="4cd60450e4dc43766e1302cd4c2beb345ace65f36d7204b0aac068d744778e85"
RUN set -euxo pipefail >/dev/null \
&& fetch "${TARGET_TOOLCHAIN_URL}" "${TARGET_TOOLCHAIN_SHA256}" /tmp/download \
&& zstd -dc /tmp/download | tar -C "${LLVM_DIR}" -x \
&& rm /tmp/download \
&& ls "${LLVM_DIR}/lib/clang/22/lib/windows/libclang_rt.builtins-x86_64.a" \
&& "${LLVM_DIR}/bin/${TRIPLET}-clang" --version

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
&& ls "${LLVM_DIR}/lib/clang/22/lib/x86_64-w64-windows-gnu/libflang_rt.runtime.a"

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
ENV WINEDEBUG="-all"
ENV WINEDLLOVERRIDES="mscoree=;mshtml="
ENV TARGET_RUNNER="wine64"


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
