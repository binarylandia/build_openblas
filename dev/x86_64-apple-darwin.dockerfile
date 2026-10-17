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
&& fetch "https://github.com/ccache/ccache/releases/download/v4.10.2/ccache-4.10.2-linux-x86_64.tar.xz" "80cab87bd510eca796467aee8e663c398239e0df1c4800a0b5dff11dca0b4f18" /tmp/download \
&& tar --strip-components=1 -C "/usr/bin" -xJf /tmp/download "ccache-4.10.2-linux-x86_64/ccache" \
&& rm /tmp/download \
&& which ccache \
&& ccache --version

RUN set -euxo pipefail >/dev/null \
&& fetch "https://github.com/Kitware/CMake/releases/download/v3.30.5/cmake-3.30.5-linux-x86_64.tar.gz" "f747d9b23e1a252a8beafb4ed2bc2ddf78cff7f04a8e4de19f4ff88e9b51dc9d" /tmp/download \
&& tar --strip-components=1 -C "/usr" -xzf /tmp/download \
&& rm /tmp/download \
&& which cmake \
&& cmake --version

RUN set -euxo pipefail >/dev/null \
&& fetch "https://github.com/binarylandia/build_gcc/releases/download/2024-11-03_12-57-14/gcc-14.2.0-host-x86_64-unknown-linux-gnu.2.17-2024-11-03_12-57-14.tar.xz" "7695cb4c68fa2e703bca4d0e5ea7bce3f6fc8ac2db507279d02818e3bd704bcc" /tmp/download \
&& tar -C "/usr" -xJf /tmp/download \
&& rm /tmp/download \
&& ls /usr/bin/gcc \
&& gcc -v \
&& ls /usr/bin/gcc-ar \
&& gcc-ar --version

RUN set -euxo pipefail >/dev/null \
&& fetch "https://github.com/binarylandia/build_llvm/releases/download/llvm-19.1.3-2024-11-03_15-15-54/llvm-19.1.3-2024-11-03_15-15-54.tar.xz" "33c9c37eecd96394cd33fd20c5cd050883c4a9b6b718746e1bdcd3c709210f2c" /tmp/download \
&& tar -C "/usr" -xJf /tmp/download \
&& rm /tmp/download \
&& ls /usr/bin/clang \
&& clang -v

ENV OSX_CROSS_PATH="/opt/osxcross"
RUN set -euxo pipefail >/dev/null \
&& mkdir -p "${OSX_CROSS_PATH}" \
&& fetch "https://github.com/binarylandia/build_osxcross/releases/download/2024-11-02_07-09-30/osxcross-202411020701-b49804a-20241102070930-2024-11-02_07-09-30.tar.xz" "51180b291740e5df18baa6fe459b691291543c1a26ee1439dad1b066a5daf2bd" /tmp/download \
&& tar -C "${OSX_CROSS_PATH}" -xJf /tmp/download \
&& rm /tmp/download

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
