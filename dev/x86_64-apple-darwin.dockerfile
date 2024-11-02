FROM ubuntu:24.04

SHELL ["bash", "-euxo", "pipefail", "-c"]

RUN set -euxo pipefail >/dev/null \
&& export DEBIAN_FRONTEND=noninteractive \
&& apt-get update -qq --yes \
&& apt-get install -qq --no-install-recommends --yes \
  bash \
  ca-certificates \
  clang \
  cmake \
  curl \
  git \
  make \
  sudo \
  tar \
  xz-utils \
>/dev/null \
&& rm -rf /var/lib/apt/lists/* \
&& apt-get clean autoclean >/dev/null \
&& apt-get autoremove --yes >/dev/null


ENV OSX_CROSS_PATH="/opt/osxcross"
RUN set -euxo pipefail >/dev/null \
&& mkdir -p "${OSX_CROSS_PATH}" \
&& curl -fsSL "https://github.com/binarylandia/build_osxcross/releases/download/osxcross-202410290447-62e500b-20241101155612-2024-11-01_15-56-10/osxcross-202410290447-62e500b-20241101155612-2024-11-01_15-56-10.tar.xz" | tar -C "${OSX_CROSS_PATH}" -xJ


COPY ./docker/files /
RUN set -euxo pipefail >/dev/null \
&& chmod +x /usr/bin/pkgutil


ENV HOSTCC="clang"

ENV OSXCROSS_MP_INC="1"
ENV MACOSX_DEPLOYMENT_TARGET="10.12"
ENV CARGO_BUILD_TARGET="x86_64-apple-darwin"
ENV OSX_TRIPLET="x86_64-apple-darwin20.2"

ENV MY_SYSROOT="${OSX_CROSS_PATH}/SDK/MacOSX11.1.sdk"
ENV PATH="${OSX_CROSS_PATH}/bin/:${PATH}"


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


ENV CC_x86_64-apple-darwin="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-gcc"
ENV CXX_x86_64-apple-darwin="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-g++"
ENV FC_x86_64-apple-darwin="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-gfortran"

ENV AR_x86_64-apple-darwin="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-ar"
ENV AS_x86_64-apple-darwin="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-as"
ENV DSYMUTIL_x86_64-apple-darwin="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-dsymutil"
ENV LD_x86_64-apple-darwin="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-ld"
ENV LIBTOOL_x86_64-apple-darwin="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-libtool"
ENV LIPO_x86_64-apple-darwin="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-lipo"
ENV NM_x86_64-apple-darwin="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-nm"
ENV OBJDUMP_x86_64-apple-darwin="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-ObjectDump"
ENV PKG_CONFIG_x86_64-apple-darwin="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-pkg-config"
ENV RANLIB_x86_64-apple-darwin="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-ranlib"
ENV STRIP_x86_64-apple-darwin="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-strip"

#ENV OPENBLAS_CC="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-clang"
#ENV OPENBLAS_CXX="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-clang++"
#ENV OPENBLAS_FC="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-gfortran"
#ENV OPENBLAS_RANLIB="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-ranlib"
#ENV OPENBLAS_NM="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-nm"
#ENV OPENBLAS_LD="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-ld"
#ENV OPENBLAS_LINKER="${OSX_CROSS_PATH}/bin/${OSX_TRIPLET}-clang"
#ENV OPENBLAS_HOSTCC="clang"
#ENV OPENBLAS_TARGET="HASWELL"

#ENV CFLAGS="-w -static -Bstatic"
#ENV CXXFLAGS="-w -static -Bstatic"
#ENV LDFLAGS="-w -static"
#ENV FCFLAGS="-w -static-libgfortran"
#ENV FFLAGS="-w -static-libgfortran"

USER ${USER}








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
