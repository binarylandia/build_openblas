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
&& curl -fsSL "https://github.com/binarylandia/build_gcc/releases/download/2024-11-01_15-42-39/gcc-14.2.0-host-x86_64-unknown-linux-gnu.2.17-2024-11-01_15-42-39.tar.xz" | tar -C "/usr" -xJ \
&& ls /usr/bin/gcc \
&& gcc -v \
&& ls /usr/bin/gcc-ar \
&& gcc-ar --version


ENV OPENBLAS_BINARY="64"
ENV OPENBLAS_CROSS="1"
ENV OPENBLAS_HOSTCC="/usr/bin/gcc"
ENV OPENBLAS_TARGET="HASWELL"


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