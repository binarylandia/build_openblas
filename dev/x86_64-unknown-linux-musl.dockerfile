FROM quay.io/pypa/manylinux2014_x86_64:2024.10.19-1

SHELL ["bash", "-euxo", "pipefail", "-c"]

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
  make \
  parallel \
  sudo \
  tar \
  xz \
>/dev/null \
&& yum clean all >/dev/null \
&& rm -rf /var/cache/yum

ENV CCACHE_DIR="/cache/ccache"
ENV CCACHE_NOCOMPRESS="1"
ENV CCACHE_MAXSIZE="50G"
RUN set -euxo pipefail >/dev/null \
&& curl -fsSL "https://github.com/ccache/ccache/releases/download/v4.10.2/ccache-4.10.2-linux-x86_64.tar.xz" | tar --strip-components=1 -C "/usr/bin" -xJ "ccache-4.10.2-linux-x86_64/ccache" \
&& which ccache \
&& ccache --version

RUN set -euxo pipefail >/dev/null \
&& curl -fsSL "https://github.com/binarylandia/build_gcc/releases/download/2024-11-03_12-57-14/gcc-14.2.0-host-x86_64-unknown-linux-gnu.2.17-2024-11-03_12-57-14.tar.xz" | tar -C "/usr" -xJ \
&& ls /usr/bin/gcc \
&& gcc -v \
&& ls /usr/bin/gcc-ar \
&& gcc-ar --version

ENV TRIPLET="x86_64-unknown-linux-musl"
ENV GCC_DIR="/opt/gcc"
RUN set -euxo pipefail >/dev/null \
&& mkdir -p "${GCC_DIR}" \
&& curl -fsSL "https://github.com/binarylandia/build_crosstool-ng/releases/download/2024-11-08_06-06-34/gcc-14.2.0-${TRIPLET}-2024-11-08_06-06-34.tar.xz" | tar -C "${GCC_DIR}" -xJ \
&& ls ${GCC_DIR}/bin/${TRIPLET}-gcc \
&& ${GCC_DIR}/bin/${TRIPLET}-gcc -v \
&& ls ${GCC_DIR}/bin/${TRIPLET}-gcc-ar \
&& ${GCC_DIR}/bin/${TRIPLET}-gcc-ar --version

ENV TRIPLET="x86_64-unknown-linux-musl"
ENV LLVM_DIR="/opt/llvm"
RUN set -euxo pipefail >/dev/null \
&& mkdir -p "${LLVM_DIR}" \
&& curl -fsSL "https://github.com/binarylandia/build_llvm/releases/download/llvm-20.1.8-2025-09-21_06-27-58/llvm-20.1.8-2025-09-21_06-27-58.tar.gz" | tar -C "${LLVM_DIR}" -xz \
&& ls "${LLVM_DIR}/bin/clang" \
&& "${LLVM_DIR}/bin/clang" --version \
&& ls "${LLVM_DIR}/bin/flang-new" \
&& "${LLVM_DIR}/bin/flang-new" --version \
&& ls "${LLVM_DIR}/bin/llvm-ar" \
&& "${LLVM_DIR}/bin/llvm-ar" --version

ENV HOSTCC="${LLVM_DIR}/bin/clang"

ENV ELFEDIT="${GCC_DIR}/bin/${TRIPLET}-elfedit"
ENV LDD="${GCC_DIR}/bin/${TRIPLET}-ldd"

ENV CC="${LLVM_DIR}/bin/clang"
ENV CXX="${LLVM_DIR}/bin/clang++"
ENV FC="${LLVM_DIR}/bin/flang-new"
ENV ADDR2LINE="${LLVM_DIR}/bin/llvm-addr2line"
ENV AR="${LLVM_DIR}/bin/llvm-ar"
ENV AS="${LLVM_DIR}/bin/llvm-as"
ENV CPP="${LLVM_DIR}/bin/clang-cpp"
ENV DLLTOOL="${LLVM_DIR}/bin/llvm-dlltool"
ENV LD="${LLVM_DIR}/bin/ld.lld"
ENV NM="${LLVM_DIR}/bin/llvm-nm"
ENV OBJCOPY="${LLVM_DIR}/bin/llvm-objcopy"
ENV OBJDUMP="${LLVM_DIR}/bin/llvm-objdump"
ENV RANLIB="${LLVM_DIR}/bin/llvm-ranlib"
ENV READELF="${LLVM_DIR}/bin/llvm-readelf"
ENV SIZE="${LLVM_DIR}/bin/llvm-size"
ENV STRINGS="${LLVM_DIR}/bin/llvm-strings"
ENV STRIP="${LLVM_DIR}/bin/llvm-strip"

RUN set -euxo pipefail >/dev/null \
&& ln -sf /usr/bin/ld "${LD}"

RUN set -euxo pipefail >/dev/null \
&& /usr/bin/ld --version


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
