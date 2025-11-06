# MITL-bootstrap

Minimal, reproducible bootstrap image for MITL projects.

MITL-bootstrap produces a tiny scratch image containing:
- musl runtime (libc, dynamic loader, crt objects) built from source
- Toybox (multi-call binary providing common Unix tools)
- featherhash shasum utilities (sha256/384/512) from ghcr.io/reactive-firewall/featherhash-shasum
- cinder-bool utilities (yes/no/true/false) from ghcr.io/reactive-firewall/cinder-bool
- a minimal /etc and /usr layout suitable for hermetic runtime usage in CI and small containers

Goals
- Small final image (scratch)
- Reproducible timestamps via MITL_DATE_EPOCH / SOURCE_DATE_EPOCH
- Multi-arch builds via Docker buildx (CI provided)
- Clear licensing and third‑party attribution

Files of interest
- Dockerfile: ./dockerfile
- Build workflow: .github/workflows/Build-Bootstraper.yaml
- Toolchain bootstrap helper: mkroot.bash
- Toybox build configuration: toybox_dot_config
- License (this repo): LICENSE

Quick usage
-----------
Pull the published image from GitHub Container Registry (GHCR):

    docker pull ghcr.io/reactive-firewall/mitl-bootstrap:<tag>

Run an interactive shell (toybox is the entrypoint and runs applets by name):

Start a bash session:

    docker run --rm -it ghcr.io/reactive-firewall/mitl-bootstrap:<tag> bash --norc -i

Run a toybox applet directly:

    docker run --rm ghcr.io/reactive-firewall/mitl-bootstrap:<tag> ls -la /

Run a command using the provided tools (example: sha256 sum):

    docker run --rm ghcr.io/reactive-firewall/mitl-bootstrap:<tag> sha256sum /path/to/file

Notes
- The image uses toybox as the entrypoint; the first argument you pass to `docker run` is treated as the toybox applet name (e.g. "bash", "ls", "printf").
- To override the toybox entrypoint and run a non-toybox binary directly, use --entrypoint:

    docker run --rm --entrypoint /bin/bash -it ghcr.io/reactive-firewall/mitl-bootstrap:<tag> --norc -i

Building locally (single-arch)
------------------------------
Requirements:
- Docker with buildx enabled
- A host toolchain that can run build-time tools (examples in Dockerfile)
- Optional: qemu for cross-arch emulation (for non-native platforms)

Example (single-arch, amd64):

    docker buildx build \
      --platform linux/amd64 \
      --build-arg TOYBOX_VERSION=0.8.12 \
      --build-arg MUSL_VER=1.2.5 \
      --build-arg TARGETARCH=amd64 \
      --build-arg TARGET_TRIPLE=x86_64-generic-none-musl \
      --build-arg HOST_TRIPLE=x86_64-alpine-linux-musl \
      --build-arg MUSL_LDLIB=ld-musl-x86_64.so.1 \
      --build-arg MITL_DATE_EPOCH=2025-01-01T00:00:00Z \
      -t ghcr.io/reactive-firewall/mitl-bootstrap:local \
      -f dockerfile \
      .

Building multi-arch (local reproduction)
----------------------------------------
The repository CI builds and pushes multi-arch images. To reproduce multi-arch locally:

    docker buildx create --use --name mitl-builder
    # install qemu registers (host privilege required)
    docker run --rm --privileged tonistiigi/binfmt --install all
    docker buildx build \
      --platform linux/amd64,linux/arm64,linux/arm/v7 \
      --build-arg TOYBOX_VERSION=0.8.12 \
      --build-arg MUSL_VER=1.2.5 \
      --build-arg MITL_DATE_EPOCH=$(git log -1 --pretty=%ct) \
      --tag ghcr.io/reactive-firewall/mitl-bootstrap:local-multiarch \
      --push \
      -f dockerfile \
      .

Reproducible builds
-------------------
This project attempts reproducibility via MITL_DATE_EPOCH and SOURCE_DATE_EPOCH.

Recommendations:
- Set MITL_DATE_EPOCH (ISO 8601) and SOURCE_DATE_EPOCH (UNIX epoch) to stable values (for example, the commit timestamp).
- Use fixed build-args (TOYBOX_VERSION, MUSL_VER, TARGET_TRIPLE, MUSL_LDLIB).
- Pin base images and external downloads (CI currently uses pinned build args and metadata).

CI / Releases
-------------
GitHub Actions workflow (./.github/workflows/Build-Bootstraper.yaml) builds and publishes multi-arch images to GHCR with the following features:
- Multi-arch build matrix (amd64, arm64, arm)
- buildx usage with caching
- SBOM generation (Syft) and vulnerability scan (Grype)
- Creates an image manifest list and publishes per-arch images

If you want to change publishing behavior (signing, registry cache, digest pinning), update the workflow.

Smoke tests (local)
-------------------
A minimal set of checks similar to CI:

    docker run -d --name mitl-test ghcr.io/reactive-firewall/mitl-bootstrap:<tag> bash -c "while true; do sleep 30; done"
    docker exec mitl-test toybox sh -c 'echo Toybox shell is working'
    docker exec mitl-test bash --version
    for cmd in bash basename cat chmod cp date find grep head mkdir mv rm sed sha256sum sha512sum true false; do
      docker exec mitl-test sh -c "which ${cmd} || echo MISSING:${cmd}"
    done
    docker stop mitl-test && docker rm -f mitl-test

Third-party components and attribution
--------------------------------------
- musl libc — https://musl.libc.org (MIT/XL)
- Toybox — https://github.com/landley/toybox (BSD/MIT-like)
- featherhash-shasum — ghcr.io/reactive-firewall/featherhash-shasum (0BSD)
- cinder-bool — ghcr.io/reactive-firewall/cinder-bool (0BSD)
- Alpine (used in build stages) — see Alpine project license(s)

See THIRD_PARTY_LICENSES.md for details and attributions.

Contributing
------------
See CONTRIBUTING.md for contribution guidelines. Small starter tasks:
- Improve README and docs (this file is a starting point)
- Pin external downloads and add checksum verification
- Make ENTRYPOINT/CMD robust and documented
- Harden reproducible-build steps and document exact inputs for deterministic images

License
-------
This repository is licensed under the terms in LICENSE (root). See THIRD_PARTY_LICENSES.md for component licenses.

---

BUILD.md
========
BUILD INSTRUCTIONS

Overview
This file documents how to build MITL-bootstrap locally and what inputs to control for reproducible outputs.

Prerequisites
- Docker 20.10+ with buildx (Docker Desktop includes buildx)
- Optional: qemu user-static (for cross-arch emulation)
- Internet access for source downloads (toybox, musl)
- Recommended: a modern host with good CPU/memory for parallel builds

Key build arguments (most are required for reproducible builds):
- TOYBOX_VERSION — tag used to download Toybox (e.g. 0.8.12)
- MUSL_VER — musl version (e.g. 1.2.5)
- TARGETARCH — short arch name passed by CI (amd64, arm64, arm)
- TARGET_TRIPLE — musl target triple (per-arch; see CI workflow for examples)
- HOST_TRIPLE — host triple used in mkroot.bash interactions
- MUSL_LDLIB — canonical ld-musl name (e.g. ld-musl-x86_64.so.1)
- MITL_DATE_EPOCH — ISO timestamp used to touch files (reproducibility)
- SOURCE_DATE_EPOCH — UNIX epoch used by some build systems (recommended)

Single-arch build example (amd64)
    docker buildx build \
      --platform linux/amd64 \
      --build-arg TOYBOX_VERSION=0.8.12 \
      --build-arg MUSL_VER=1.2.5 \
      --build-arg TARGETARCH=amd64 \
      --build-arg TARGET_TRIPLE=x86_64-generic-none-musl \
      --build-arg HOST_TRIPLE=x86_64-alpine-linux-musl \
      --build-arg MUSL_LDLIB=ld-musl-x86_64.so.1 \
      --build-arg MITL_DATE_EPOCH=2025-01-01T00:00:00Z \
      -t mitl-bootstrap:local \
      -f dockerfile \
      .

Multi-arch build (CI-style)
- Create a buildx builder and register QEMU:

    docker buildx create --use --name mitl-builder
    docker run --rm --privileged tonistiigi/binfmt --install all

- Build and push:

    docker buildx build \
      --platform linux/amd64,linux/arm64,linux/arm/v7 \
      --build-arg TOYBOX_VERSION=0.8.12 \
      --build-arg MUSL_VER=1.2.5 \
      --build-arg MITL_DATE_EPOCH=$(git log -1 --pretty=%ct) \
      --tag ghcr.io/reactive-firewall/mitl-bootstrap:local-multiarch \
      --push \
      -f dockerfile \
      .

Reproducibility tips
- Use the same MITL_DATE_EPOCH and SOURCE_DATE_EPOCH values across builds.
- Pin versions and, if possible, verify downloads via checksum.
- Ensure build caches are either fully empty (clean build) or consistent.

Troubleshooting
- If builds fail due to cross-compile toolchain issues, check TARGET_TRIPLE and MUSL_LDLIB values.
- If qemu errors occur, ensure binfmt/qemu is registered correctly and that privileged mode was used when installing binfmt.

USAGE.md
========
USAGE AND EXAMPLES

Run interactive shells
- Start an interactive bash session:

    docker run --rm -it ghcr.io/reactive-firewall/mitl-bootstrap:<tag> bash --norc -i

- Start a toybox sh session:

    docker run --rm -it ghcr.io/reactive-firewall/mitl-bootstrap:<tag> sh

Run single commands
- List root:

    docker run --rm ghcr.io/reactive-firewall/mitl-bootstrap:<tag> ls -la /

- Compute a SHA256 sum:

    docker run --rm ghcr.io/reactive-firewall/mitl-bootstrap:<tag> sha256sum /some/file

Entrypoint behavior
- The image uses /usr/bin/toybox as the ENTRYPOINT. toybox interprets argv[1] as the applet name. Example:

    docker run --rm ghcr.io/reactive-firewall/mitl-bootstrap:<tag> printf 'hello\n'

Overriding entrypoint
- If you need to run a non-toybox binary or set a different process as PID 1, use --entrypoint:

    docker run --rm --entrypoint /bin/bash -it ghcr.io/reactive-firewall/mitl-bootstrap:<tag> --norc -i

Automated smoke test
- Example script to validate basic functionality (adapt to CI):

    #!/bin/bash
    TAG=<tag>
    docker run -d --name mitl-test ghcr.io/reactive-firewall/mitl-bootstrap:${TAG} bash -c "while true; do sleep 30; done"
    docker exec mitl-test toybox sh -c 'echo Toybox shell is working'
    docker exec mitl-test bash --version
    for cmd in bash basename cat chmod cp date find grep head mkdir mv rm sed sha256sum sha512sum true false; do
      docker exec mitl-test sh -c "which ${cmd} || echo MISSING:${cmd}"
    done
    docker stop mitl-test && docker rm -f mitl-test

CONTRIBUTING.md
===============

Welcome and thank you for considering contributions.

How to contribute
1. Fork the repository.
2. Create a topic branch (prefix with feat/, fix/, docs/, ci/).
3. Make small, focused changes and include tests or verification steps when applicable.
4. Open a pull request describing the change and the rationale.

PR guidance
- Keep commits small and focused.
- Use descriptive commit messages and a clear PR title/body.
- If the change modifies the build or runtime behavior, explain the compatibility implications and how to test locally.
- When adding or updating external dependencies, include license information and a checksum where feasible.
- The repository contains a GitHub Actions workflow that will build and run smoke tests. Ensure your change passes CI.

Code of conduct
- Be respectful, constructive, and collaborative.

THIRD_PARTY_LICENSES.md
=======================
Third-party components and licenses used or referenced by MITL-bootstrap.

musl libc
- Source: https://musl.libc.org
- License: MIT/Expat-like
- Notes: musl is built from source in the Dockerfile. Include the musl LICENSE in redistributed artifacts if you repackage.

Toybox
- Source: https://github.com/landley/toybox
- License: BSD/MIT-like (see toybox repository for exact text)
- Notes: toybox is built from a tarball downloaded in the build stage. Include toybox license text in redistributions.

featherhash-shasum
- Source: ghcr.io/reactive-firewall/featherhash-shasum
- License: 0BSD
- Notes: used to provide sha256/384/512 sum commands in the final image.

cinder-bool
- Source: ghcr.io/reactive-firewall/cinder-bool
- License: 0BSD
- Notes: provides basic boolean utilities (yes/no/true/false) in the final image.

Alpine (build-stage base images)
- Source: https://alpinelinux.org
- License: Alpine packages vary; build uses specific packages. Check package licenses if bundling binaries outside the image.

Attribution and redistribution
- When redistributing the final artifact outside the container image (e.g., repackaging or embedding libraries), include each component's license and attribution where required by that license.
- Prefer including full license texts for musl and toybox alongside this repository's LICENSE when creating a release tarball.

