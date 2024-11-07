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
  glibc-static \
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
&& curl -fsSL "https://github.com/Kitware/CMake/releases/download/v3.30.5/cmake-3.30.5-linux-x86_64.tar.gz" | tar --strip-components=1 -C "/usr" -xz \
&& which cmake \
&& cmake --version

RUN set -euxo pipefail >/dev/null \
&& curl -fsSL "https://github.com/binarylandia/build_gcc/releases/download/2024-11-03_12-57-14/gcc-14.2.0-host-x86_64-unknown-linux-gnu.2.17-2024-11-03_12-57-14.tar.xz" | tar -C "/usr" -xJ \
&& ls /usr/bin/gcc \
&& gcc -v \
&& ls /usr/bin/gcc-ar \
&& gcc-ar --version

RUN set -euxo pipefail >/dev/null \
&& curl -fsSL "https://github.com/binarylandia/build_llvm/releases/download/llvm-19.1.3-2024-11-03_15-15-54/llvm-19.1.3-2024-11-03_15-15-54.tar.xz" | tar -C "/usr" -xJ \
&& ls /usr/bin/clang \
&& clang -v

ENV OSX_CROSS_PATH="/opt/osxcross"
RUN set -euxo pipefail >/dev/null \
&& mkdir -p "${OSX_CROSS_PATH}" \
&& curl -fsSL "https://github.com/binarylandia/build_osxcross/releases/download/2024-11-02_07-09-30/osxcross-202411020701-b49804a-20241102070930-2024-11-02_07-09-30.tar.xz" | tar -C "${OSX_CROSS_PATH}" -xJ

ENV OSXCROSS_MP_INC="1"
ENV MACOSX_DEPLOYMENT_TARGET="10.12"
ENV OSX_TRIPLET="x86_64-apple-darwin20.2"

ENV MY_SYSROOT="${OSX_CROSS_PATH}/SDK/MacOSX11.1.sdk"
ENV PATH="${OSX_CROSS_PATH}/bin/:${PATH}"

ENV HOSTCC="/usr/bin/gcc"
ENV CC="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-gcc"
ENV CXX="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-g++"
ENV FC="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-gfortran"
ENV AR="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-ar"
ENV AS="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-as"
ENV DSYMUTIL="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-dsymutil"
ENV LD="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-ld"
ENV LIBTOOL="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-libtool"
ENV LIPO="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-lipo"
ENV NM="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-nm"
ENV OBJDUMP="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-ObjectDump"
ENV PKG_CONFIG="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-pkg-config"
ENV RANLIB="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-ranlib"
ENV STRIP="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-strip"


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
