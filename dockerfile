# Use Alpine as the base image for the build environment
FROM alpine:latest AS builder

# Set environment variables
ENV TOYBOX_VERSION=0.8.12
ENV PATH="/usr/local/bin:$PATH"
ENV CC=clang
ENV CXX=clang++
ENV AR=llvm-ar
ENV RANLIB=llvm-ranlib
ENV LDFLAGS="-fuse-ld=lld"
ENV BSD=/usr/include/bsd
ENV LINUX=/usr/include/linux

# Install necessary packages
RUN apk add --no-cache \
    llvm \
    clang \
    build-base \
    git \
    musl-dev \
    linux-headers \
    bash \
    genext2fs \
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
RUN make V=1 CC=clang CFLAGS="-O2 -fPIC -fno-common" AR=llvm-ar LINUX="${LINUX}" LDFLAGS="${LDFLAGS}" toybox root && \
    mkdir -p /output/usr/bin /output/etc /output/lib && \
    make install PREFIX=/usr DESTDIR=/output

# Collect runtime shared libraries used by the built toybox and copy them into /output/lib
RUN mv /opt/toybox/root/host/fs /output && \
    ls -lap /output/usr && \
    ls -lap /output/usr/bin

# Minimal etc
RUN printf "root:x:0:0:root:/root:/bin/sh\n" > /output/etc/passwd && \
    printf "/dev/sda / ext4 defaults 0 1\n" > /output/etc/fstab

# Stage 2: Create the final image
FROM scratch AS mitl-bootstrap

# Copy built files
COPY --from=builder /output/ /

# Ensure toybox is reachable at /bin/toybox (symlink if needed)
COPY --from=builder /output/usr/bin/toybox /bin/toybox

# Set the entry point to Toybox
ENTRYPOINT ["/usr/bin/toybox"]
CMD ["sh"]
