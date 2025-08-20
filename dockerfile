# Use Alpine as the base image for the build environment
FROM alpine:latest as builder

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
    tar

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

# Ensure a deterministic default config if none supplied
RUN if [ ! -f .config ]; then make defconfig; fi

# Build static toybox binary and install into /output
# Use V=1 for verbose output if errors occur
# TOYBOX_STATIC=1 forces static linking (recommended for scratch)
RUN make V=1 CFLAGS="-static -Os" LDFLAGS="-static" TOYBOX_STATIC=1 \
 && mkdir -p /output/bin /output/etc \
 && make install PREFIX=/usr DESTDIR=/output

# create minimal /etc/passwd and fstab for runtime
RUN printf "root:x:0:0:root:/root:/bin/sh\n" > /output/etc/passwd \
 && printf "%s\n" "/dev/sda / ext4 defaults 0 1" > /output/etc/fstab


# Stage 2: Create the final image
FROM scratch as mitl-bootstrap

# Copy the root filesystem from the builder stage
COPY --from=builder /output/rootfs /

# Set the entry point to Toybox
ENTRYPOINT ["/usr/bin/toybox"]
CMD ["sh"]
