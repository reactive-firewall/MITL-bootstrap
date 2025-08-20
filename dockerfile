# Use Alpine as the base image for the build environment
FROM alpine:latest AS builder

# Set environment variables
ENV TOYBOX_VERSION=0.8.12
ENV PATH="/usr/local/bin:$PATH"
ENV CC=clang
ENV CXX=clang++
ENV AR=llvm-ar
ENV RANLIB=llvm-ranlib

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
    libbsd-dev

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

# Force disabling external iconv if present in .config
RUN if [ -f .config ]; then \
      sed -i 's/^CONFIG_ICONV=.*/CONFIG_ICONV=n/' .config || true; \
      sed -i 's/^CONFIG_TOYBOX_ICONV=.*/CONFIG_TOYBOX_ICONV=n/' .config || true; \
    else \
      make defconfig; \
    fi

# Verify config
RUN grep -E '^CONFIG_(ICONV|TOYBOX_ICONV)=' .config || true

# Build (dynamic): do NOT pass -static or TOYBOX_STATIC
RUN make V=1 CC=clang CFLAGS="-O2 -fPIC" LDFLAGS="" \
 && mkdir -p /output/usr/bin /output/etc /output/lib \
 && make install PREFIX=/usr DESTDIR=/output

# Collect runtime shared libraries used by the built toybox and copy them into /output/lib
RUN set -e; \
    BIN=/output/usr/bin/toybox; \
    if [ ! -f "$BIN" ]; then echo "toybox binary missing"; exit 1; fi; \
    ldd "$BIN" | awk '/=>/ {print $(NF-1)}; /ld-musl/ {print $1}' | sort -u > /tmp/deps.txt; \
    while read -r lib; do \
      [ -z "$lib" ] && continue; \
      cp -L --parents "$lib" /output || true; \
    done < /tmp/deps.txt; \
    # ensure /lib and /usr/lib exist
    mkdir -p /output/lib /output/usr/lib

# Minimal etc
RUN printf "root:x:0:0:root:/root:/bin/sh\n" > /output/etc/passwd \
 && printf "/dev/sda / ext4 defaults 0 1\n" > /output/etc/fstab

# Stage 2: Create the final image
FROM scratch AS mitl-bootstrap

# Copy built files
COPY --from=builder /output/ /

# Ensure toybox is reachable at /bin/toybox (symlink if needed)
COPY --from=builder /output/usr/bin/toybox /bin/toybox

# Set the entry point to Toybox
ENTRYPOINT ["/usr/bin/toybox"]
CMD ["sh"]
