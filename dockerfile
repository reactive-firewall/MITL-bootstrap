# syntax=docker/dockerfile:1
ARG TOYBOX_VERSION=${TOYBOX_VERSION:-"0.8.12"}

# version is passed through by Docker.
# shellcheck disable=SC2154
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
      -e 's/^CONFIG_PING=.*/CONFIG_PING=n/' \
      .config || true ; \
    else \
      make defconfig; \
    fi

RUN rm -rf generated flags.* || true && make oldconfig || true

# build with clang and lld
RUN make V=1 CC=clang CFLAGS="-fno-math-errno -fstrict-aliasing -fPIC -fno-common" AR=llvm-ar LINUX="${LINUX}" LDFLAGS="${LDFLAGS}" toybox root && \
    mkdir -p /output/usr/bin /output/etc /output/lib && \
    make install PREFIX=/usr DESTDIR=/output && \
    mv /opt/toybox/root/host/fs /output

# Minimal etc
RUN printf "root:x:0:0:root:/root:/bin/sh\n" > /output/fs/etc/passwd && \
    printf "/dev/sda / ext4 defaults 0 1\n" > /output/fs/etc/fstab

# Stage 2: Create the final image
# shellcheck disable=SC2154
FROM --platform="linux/${TARGETARCH}" scratch AS mitl-bootstrap

# set inherited values
LABEL version="0.5"
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

SHELL [ "/bin/bash", "--norc", "-l", "-c" ]

# Set the entry point to Toybox
ENTRYPOINT ["/usr/bin/toybox"]
ENV BASH='/bin/bash'
ENV HOSTNAME="base-builder"
CMD [ "/bin/bash", "--norc", "-l", "-c", "'exec -a bash /bin/bash -il'" ]
