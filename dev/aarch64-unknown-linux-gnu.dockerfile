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

ENV TRIPLET="aarch64-unknown-linux-gnu"
ENV GCC_DIR="/opt/gcc"
RUN set -euxo pipefail >/dev/null \
&& mkdir -p "${GCC_DIR}" \
&& curl -fsSL "https://github.com/binarylandia/build_crosstool-ng/releases/download/2024-10-30_09-44-58/gcc-9.5.0-${TRIPLET}-2024-10-30_09-44-58.tar.xz" | tar -C "${GCC_DIR}" -xJ \
&& ls ${GCC_DIR}/bin/${TRIPLET}-gcc \
&& ${GCC_DIR}/bin/${TRIPLET}-gcc -v \
&& ls ${GCC_DIR}/bin/${TRIPLET}-gcc-ar \
&& ${GCC_DIR}/bin/${TRIPLET}-gcc-ar --version

ENV CC="${GCC_DIR}/bin/${TRIPLET}-cc"
ENV CXX="${GCC_DIR}/bin/${TRIPLET}-g++"
ENV FC="${GCC_DIR}/bin/${TRIPLET}-gfortran"
ENV ADDR2LINE="${GCC_DIR}/bin/${TRIPLET}-addr2line"
ENV AR="${GCC_DIR}/bin/${TRIPLET}-gcc-ar"
ENV AS="${GCC_DIR}/bin/${TRIPLET}-as"
ENV CPP="${GCC_DIR}/bin/${TRIPLET}-cpp"
ENV ELFEDIT="${GCC_DIR}/bin/${TRIPLET}-elfedit"
ENV LD="${GCC_DIR}/bin/${TRIPLET}-ld"
ENV LDD="${GCC_DIR}/bin/${TRIPLET}-ldd"
ENV NM="${GCC_DIR}/bin/${TRIPLET}-gcc-nm"
ENV OBJCOPY="${GCC_DIR}/bin/${TRIPLET}-objcopy"
ENV OBJDUMP="${GCC_DIR}/bin/${TRIPLET}-objdump"
ENV RANLIB="${GCC_DIR}/bin/${TRIPLET}-gcc-ranlib"
ENV READELF="${GCC_DIR}/bin/${TRIPLET}-readelf"
ENV SIZE="${GCC_DIR}/bin/${TRIPLET}-size"
ENV STRINGS="${GCC_DIR}/bin/${TRIPLET}-strings"
ENV STRIP="${GCC_DIR}/bin/${TRIPLET}-strip"

ENV OPENBLAS_BINARY="64"
ENV OPENBLAS_CROSS="1"
ENV OPENBLAS_HOSTCC="/usr/bin/gcc"
ENV OPENBLAS_TARGET="ARMV8"


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
