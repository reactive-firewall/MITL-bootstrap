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
    ufs-utils  # Install UFS utilities

# Download and install Toybox
RUN mkdir -p /opt && \
    cd /opt && \
    curl --url "https://github.com/landley/toybox/archive/refs/tags/${TOYBOX_VERSION}.tar.gz" \
    -o toybox-${TOYBOX_VERSION}.tar.gz && \
    tar -xzf toybox-${TOYBOX_VERSION}.tar.gz && \
    rm toybox-${TOYBOX_VERSION}.tar.gz && \
    cd toybox-${TOYBOX_VERSION} && \
    make && \
    make install

# Create a UFS filesystem
RUN mkdir -p /rootfs && \
    mkfs.ufs /rootfs.img  # Create a UFS image file

# Mount the UFS filesystem
RUN mkdir -p /mnt/ufs && \
    mount -o loop /rootfs.img /mnt/ufs && \
    cp /usr/local/bin/toybox /mnt/ufs/bin/ && \
    ln -s /bin/toybox /mnt/ufs/bin/{sh,ls,cp,mv,rm} && \
    echo "root:x:0:0:root:/root:/bin/sh" > /mnt/ufs/etc/passwd && \
    echo "/dev/sda / ufs defaults 0 1" > /mnt/ufs/etc/fstab && \
    umount /mnt/ufs  # Unmount the UFS filesystem

# Copy just the built root filesystem to a clean new stage
FROM scratch as mitl-bootstrap

# Copy the UFS image from the builder stage
COPY --from=builder /rootfs.img /

# Set the entrypoint to Toybox
ENTRYPOINT ["/bin/toybox"]
