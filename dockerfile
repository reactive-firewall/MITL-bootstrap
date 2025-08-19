# Use Alpine as the base image for the build environment
FROM alpine:latest as builder

# Set environment variables
ENV BUILDROOT_VERSION=2025.02
ENV TOOLCHAIN_PREFIX=/usr/local/toolchain
ENV PATH="$TOOLCHAIN_PREFIX/bin:$PATH"

# Install necessary packages
RUN apk add --no-cache \
    build-base \
    clang \
    musl-dev \
    git \
    wget \
    bash \
    make \
    cmake \
    python3 \
    curl

# Download and install Buildroot
RUN mkdir -p /opt && \
    cd /opt && \
    wget https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.gz && \
    tar -xzf buildroot-${BUILDROOT_VERSION}.tar.gz && \
    rm buildroot-${BUILDROOT_VERSION}.tar.gz

# Set up Buildroot configuration
COPY bootstrap_defconfig /opt/buildroot-${BUILDROOT_VERSION}/configs/bootstrap_defconfig

# Set the working directory
WORKDIR /opt/buildroot-${BUILDROOT_VERSION}

# Build the toolchain and packages
RUN make bootstrap_defconfig && \
    make

# Copy just the built root filesystem to a clean new stage
FROM scratch as mitl-bootstrap

# Copy the built root filesystem from the builder stage
COPY --from=builder /opt/buildroot-${BUILDROOT_VERSION}/output/images/rootfs.tar /rootfs.tar

# Extract the root filesystem
RUN tar -xf /rootfs.tar -C /

# Set the entrypoint to Toybox
ENTRYPOINT ["/bin/toybox"]
