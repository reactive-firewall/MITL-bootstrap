# Use Alpine as the base image for the build environment
FROM alpine:latest as builder

# Set environment variables
ENV TOYBOX_VERSION=0.8.5
ENV PATH="/usr/local/bin:$PATH"

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

# Set the working directory
WORKDIR /build

# Copy the Toybox configuration file
COPY toybox_dot_config .config

# Download Toybox and musl
RUN mkdir -p /opt && \
    cd /opt && \
    curl -fsSL \
    --url "https://github.com/landley/toybox/archive/refs/tags/${TOYBOX_VERSION}.tar.gz" \
    -o toybox-${TOYBOX_VERSION}.tar.gz && \
    tar -xzf toybox-${TOYBOX_VERSION}.tar.gz && \
    rm toybox-${TOYBOX_VERSION}.tar.gz && \
    cd toybox-${TOYBOX_VERSION} && \
    # Set environment variables for Clang
    export CC=clang && \
    export CXX=clang++ && \
    export AR=llvm-ar && \
    export RANLIB=llvm-ranlib && \
    # Compile Toybox
    make && \
    make install DESTDIR=/output

# Mount the UFS filesystem
RUN mkdir -p /output/rootfs/{bin,etc,lib,proc,sys} && \
    cp /output/bin/toybox /output/rootfs/bin/ && \
    # Copy musl libraries
    cp -r /lib/ /output/rootfs/lib/ && \
    ln -s /bin/toybox /rootfs/bin/{sh,ls,cp,mv,rm} && \
    echo "root:x:0:0:root:/root:/bin/sh" > /rootfs/etc/passwd && \
    echo "/dev/sda / ext4 defaults 0 1" > /rootfs/etc/fstab

# Stage 2: Create the final image
FROM scratch as mitl-bootstrap

# Copy the root filesystem from the builder stage
COPY --from=builder /output/rootfs /

# Set the entry point to Toybox
ENTRYPOINT ["/bin/toybox"]
CMD ["sh"]
