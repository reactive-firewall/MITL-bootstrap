# syntax=docker/dockerfile:1
ARG TOYBOX_VERSION=${TOYBOX_VERSION:-"0.8.12"}

# version is passed through by Docker.
# shellcheck disable=SC2154
ARG MUSL_VER=${MUSL_VER:-"1.2.5"}
ARG MUSL_PREFIX=/usr/local/musl-llvm-staging

# Stage 1: Build Musl
# Use MIT licensed Alpine as the base image for the build environment
# shellcheck disable=SC2154
FROM --platform="linux/${TARGETARCH}" alpine:latest AS musl-builder

ENV MUSL_VER=${MUSL_VER:-"1.2.5"}
ENV MUSL_PREFIX=${MUSL_PREFIX}

RUN set -eux \
    && apk add --no-cache \
        clang \
        llvm \
        lld \
        make \
        binutils \
        curl \
        ca-certificates \
        build-base \
        gzip \
        perl \
        paxctl \
    && mkdir -p /build

WORKDIR /build
ENV export CC=clang
ENV export AR=llvm-ar
ENV export RANLIB=llvm-ranlib
ENV export LD=ld.lld
ENV LDFLAGS="-fuse-ld=lld"

# Download musl
RUN set -eux \
    && curl -fsSLO https://musl.libc.org/releases/musl-${MUSL_VER}.tar.gz \
    && tar xf musl-${MUSL_VER}.tar.gz \
    && mv musl-${MUSL_VER} musl

WORKDIR /build/musl

# Configure, build, and install musl with shared enabled (default) using LLVM tools
RUN mkdir -p ${MUSL_PREFIX} && \
    ./configure --prefix=${MUSL_PREFIX} && \
    make -j"$(nproc)" && \
    make install

# Ensure we have the dynamic loader and libs present (example paths)
RUN ls -l ${MUSL_PREFIX}/lib || true \
    && file ${MUSL_PREFIX}/lib/* || true

# Strip unneeded symbols from shared objects to save space (optional)
RUN set -eux \
    && if command -v llvm-strip >/dev/null 2>&1; then \
         find ${MUSL_PREFIX}/lib -type f -name "*.so*" -exec llvm-strip --strip-unneeded {} + || true; \
       else \
         find ${MUSL_PREFIX}/lib -type f -name "*.so*" -exec strip --strip-unneeded {} + || true; \
       fi


# Stage 2: Build toybox based filesystem
# Use MIT licensed Alpine as the base image for the build environment
# shellcheck disable=SC2154
FROM --platform="linux/${TARGETARCH}" alpine:latest AS builder

# Set environment variables
ENV TOYBOX_VERSION=${TOYBOX_VERSION:-"0.8.12"}
ENV PATH="/usr/local/bin:$PATH"
ENV CC=clang
ENV CXX=clang++
ENV AR=llvm-ar
ENV RANLIB=llvm-ranlib
ENV LDFLAGS="-fuse-ld=lld"
ENV BSD=/usr/include/bsd
ENV LINUX=/usr/include/linux
ENV MUSL_VER=${MUSL_VER:-"1.2.5"}
ENV MUSL_PREFIX=${MUSL_PREFIX}

# Install necessary packages
# llvm - LLVM-apache-2
# clang - llvm-apache-2
# lld - llvm-apache-2
# build-base - MIT
# git - LGPL2+ - do not bundle - used to clone during bootstrap
# musl-dev - MIT
# linux-headers - GPL-2.0-only - do not bundle - only used until toolbox bash is compiled
# libbsd-dev - BSD-3-Clause
# bash - GPL-3.0 - do not bundle - only until toolbox bash is compiled to run bootstrap scripts
# curl - curl License / MIT
# tar - GPL-3.0-or-later - do not bundle - used to unarchive during bootstrap
# openssl-dev - Apache-2.0
# zlib-dev - zlib license

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add \
    llvm \
    clang \
    build-base \
    git \
    musl-dev \
    linux-headers \
    bash \
    curl \
    tar \
    openssl-dev \
    libbsd-dev \
    lld \
    zlib-dev

# Download Toybox and musl
RUN mkdir -p /opt && \
    cd /opt && \
    curl -fsSL \
    --url "https://github.com/landley/toybox/archive/refs/tags/${TOYBOX_VERSION}.tar.gz" \
    -o toybox-${TOYBOX_VERSION}.tar.gz && \
    tar -xzf toybox-${TOYBOX_VERSION}.tar.gz && \
    rm toybox-${TOYBOX_VERSION}.tar.gz && \
    mv /opt/toybox-${TOYBOX_VERSION} /opt/toybox

WORKDIR /opt/toybox

SHELL [ "/bin/sh", "-c" ]

# Copy the Toybox configuration file
COPY toybox_dot_config .config

# Copy the pre-stage tools
COPY cmd-scout.bash /usr/bin/cmd-scout.bash
COPY cmd-trebuchet.bash /usr/bin/cmd-trebuchet.bash
COPY mkroot.bash /usr/bin/mkroot.bash

RUN chmod 555 /usr/bin/cmd-scout.bash && \
    chmod 555 /usr/bin/cmd-trebuchet.bash && \
    chmod 555 /usr/bin/mkroot.bash

# Force-disable optional libraries/features that cause probe failures
RUN if [ -f .config ]; then \
      sed -i \
      -e 's/^CONFIG_SELINUX=.*/CONFIG_SELINUX=n/' \
      -e 's/^CONFIG_ICONV=.*/CONFIG_ICONV=n/' \
      -e 's/^CONFIG_TOYBOX_ICONV=.*/CONFIG_TOYBOX_ICONV=n/' \
      -e 's/^CONFIG_LIBZ=.*/CONFIG_LIBZ=n/' \
      -e 's/^CONFIG_LZ4=.*/CONFIG_LZ4=n/' \
      -e 's/^CONFIG_CRYPTO=.*/CONFIG_CRYPTO=n/' \
      -e 's/^CONFIG_TOYBOX_LIBCRYPTO=.*/CONFIG_TOYBOX_LIBCRYPTO=n/' \
      -e 's/^CONFIG_SELINUX=.*/CONFIG_SELINUX=n/' \
      -e 's/^CONFIG_TOYBOX_SELINUX=.*/CONFIG_TOYBOX_SELINUX=n/' \
      -e 's/^CONFIG_FEATURE_PING=.*/CONFIG_FEATURE_PING=n/' \
      -e 's/^CONFIG_GZIP=.*/CONFIG_GZIP=n/' \
      -e 's/^CONFIG_GUNZIP=.*/CONFIG_GUNZIP=n/' \
      -e 's/^CONFIG_PING=.*/CONFIG_PING=n/' \
      .config || true ; \
    else \
      make defconfig; \
    fi

RUN rm -rf generated flags.* || true && make oldconfig || true

# build with clang and lld
RUN make V=1 CC=clang CFLAGS="-fno-math-errno -fstrict-aliasing -fPIC -fno-common" AR=llvm-ar LINUX="${LINUX}" LDFLAGS="${LDFLAGS}" toybox root && \
    mkdir -p /output/usr/bin /output/etc /output/lib && \
    make install PREFIX=/usr DESTDIR=/output

ENV HOST_TOOLCHAIN_PATH="/opt/toybox/root/host/fs"
ENV PREFIX="/usr"
RUN mkdir /output/fs
ENV DESTDIR="/output/fs"

# Minimal etc
RUN /usr/bin/mkroot.bash && \
    printf "root:x:0:0:root:/root:/bin/sh\n" > /output/fs/etc/passwd && \
    printf "/dev/sda / ext4 defaults 0 1\n" > /output/fs/etc/fstab

# Copy musl runtime artifacts from builder:
# - dynamic loader (ld-musl-*.so.1)
# - libmusl shared object(s) (libc.so.*)
# - crt*.o (for static linking if needed)
# - headers
COPY --from=musl-builder ${MUSL_PREFIX}/lib/ld-musl-*.so.* /output/fs/lib/
COPY --from=musl-builder ${MUSL_PREFIX}/lib/libc.so* /output/fs/usr/lib/
COPY --from=musl-builder ${MUSL_PREFIX}/lib/crt1.o ${MUSL_PREFIX}/lib/crti.o ${MUSL_PREFIX}/lib/crtn.o /output/fs/lib/ || true
COPY --from=musl-builder ${MUSL_PREFIX}/include /output/fs/usr/include

# Some systems expect /lib64 -> /lib for x86_64. Create symlink if appropriate.
RUN set -eux; \
    if [ "$(uname -m)" = "x86_64" ]; then \
      [ -d /output/fs/lib64 ] || ln -s /output/fs/lib /lib64; \
    fi

# Ensure loader has canonical name (example: /lib/ld-musl-x86_64.so.1)
RUN set -eux \
    && for f in /output/fs/lib/ld-musl-*; do \
         ln -fns "$f" /output/fs/lib/ld-musl.so.1 || true; \
       done || true

# Stage 3: Create the final image
# shellcheck disable=SC2154
FROM --platform="linux/${TARGETARCH}" scratch AS mitl-bootstrap

# set inherited values
LABEL version="0.8"
LABEL org.opencontainers.image.title="MITL-bootstrap"
LABEL org.opencontainers.image.description="Custom Bootstrap MITL image with toybox installed."
LABEL org.opencontainers.image.vendor="individual"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="mitl-maintainers@users.noreply.github.com"
LABEL maintainer="mitl-maintainers@users.noreply.github.com"

# Copy built files
COPY --from=builder /output/fs /

# Ensure toybox is reachable at /bin/toybox (symlink if needed)
COPY --from=builder /output/fs/usr/bin/toybox /bin/toybox

SHELL [ "/bin/bash", "--norc", "-c" ]

# Set the entry point to Toybox
ENTRYPOINT ["/usr/bin/toybox"]
ENV BASH='/bin/bash'
ENV HOSTNAME="MITL-bootstrap"
CMD [ "/bin/bash", "--norc", "-c", "'exec -a bash /bin/bash -i'" ]
