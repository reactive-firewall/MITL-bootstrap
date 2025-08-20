# Use Alpine as the base image for the build environment
FROM alpine:latest as builder

# Set environment variables
ENV TOYBOX_VERSION=0.8.5
ENV PATH="/usr/local/bin:$PATH"

# Install necessary packages
RUN apk add --no-cache \
    build-base \
    clang \
    musl-dev \
    bash \
    make \
    curl \
    tar

# Download and install Toybox
RUN mkdir -p /opt && \
    cd /opt && \
    curl -fsSL \
    --url "https://github.com/landley/toybox/archive/refs/tags/${TOYBOX_VERSION}.tar.gz" \
    -o toybox-${TOYBOX_VERSION}.tar.gz && \
    tar -xzf toybox-${TOYBOX_VERSION}.tar.gz && \
    rm toybox-${TOYBOX_VERSION}.tar.gz && \
    cd toybox-${TOYBOX_VERSION} && \
    make defconfig && \
    make && \
    make install

# Mount the UFS filesystem
RUN mkdir -p /rootfs/{bin,etc,lib,usr/bin} && \
    cp /usr/local/bin/toybox /rootfs/bin/ && \
    ln -s /bin/toybox /rootfs/bin/{sh,ls,cp,mv,rm} && \
    echo "root:x:0:0:root:/root:/bin/toolbox" > /rootfs/etc/passwd && \
    echo "/dev/sda / ext4 defaults 0 1" > /rootfs/etc/fstab

# Copy just the built root filesystem to a clean new stage
FROM scratch as mitl-bootstrap

# Copy the UFS image from the builder stage
COPY --from=builder /rootfs /

# Set the entrypoint to Toybox
ENTRYPOINT ["/bin/toybox"]
