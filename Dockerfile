# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM rust:1-slim-trixie AS builder
ARG TARGETARCH
ENV CARGO_HOME=/root/.cargo
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y cmake make libutfcpp-dev unzip git build-essential pkg-config clang yasm wget libssl-dev
RUN wget -O taglib.zip https://github.com/taglib/taglib/archive/refs/tags/v2.2.1.zip && \
    unzip taglib.zip && \
    cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF taglib-2.2.1 && \
    make -j && \
    make install
WORKDIR /build
ADD . .
WORKDIR /build/cli
ARG BUILD_ARGS=--all-features
ARG ENABLE_CUDA=0
ARG ENABLE_ROCM=0
ENV ORT_CUDA_VERSION=13
RUN --mount=type=cache,target=/build/target/release/build \
    --mount=type=cache,target=/build/target/release/deps \
    --mount=type=cache,target=/build/target/release/incremental \
    --mount=type=cache,target=/build/target/CACHEDIR.TAG \
    --mount=type=cache,target=/build/cli/target/release/build \
    --mount=type=cache,target=/build/cli/target/release/deps \
    --mount=type=cache,target=/build/cli/target/release/incremental \
    --mount=type=cache,target=/build/cli/target/CACHEDIR.TAG \
    --mount=type=cache,target=/root/.cargo/ \
    cargo build --release --bins $BUILD_ARGS
RUN --mount=type=cache,target=/build/target/release/build \
    --mount=type=cache,target=/build/target/release/deps \
    --mount=type=cache,target=/build/target/release/incremental \
    --mount=type=cache,target=/build/target/CACHEDIR.TAG \
    --mount=type=cache,target=/build/cli/target/release/build \
    --mount=type=cache,target=/build/cli/target/release/deps \
    --mount=type=cache,target=/build/cli/target/release/incremental \
    --mount=type=cache,target=/build/cli/target/CACHEDIR.TAG \
    --mount=type=cache,target=/root/.cargo/ \
    cargo test --release --workspace $BUILD_ARGS

FROM --platform=$BUILDPLATFORM debian:trixie-slim
ARG TARGETARCH
ARG BUILD_ARGS=--all-features
ARG ENABLE_CUDA=0
ARG ENABLE_ROCM=0
RUN --mount=type=cache,id=final,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=final,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y ca-certificates wget gpg && \
    if [ "$ENABLE_CUDA" = "1" ]; then \
        wget https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb && \
        wget https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/libcudnn9-cuda-13_9.22.0.52-1_amd64.deb && \
        apt-get install -f ./cuda-keyring_1.1-1_all.deb ./libcudnn9-cuda-13_9.22.0.52-1_amd64.deb && \
        apt-get update && \
        apt-get install -y libcufft-13-2 libcublas-13-2 cuda-cudart-13-2 libcurand-13-2; \
    fi && \
    if [ "$ENABLE_ROCM" = "1" ]; then \
        mkdir -p /etc/apt/keyrings && \
        wget -q -O- https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor > /etc/apt/keyrings/rocm.gpg && \
        echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2 noble main" > /etc/apt/sources.list.d/rocm.list && \
        printf '%s\n' 'Package: *' 'Pin: release o=repo.radeon.com' 'Pin-Priority: 600' > /etc/apt/preferences.d/rocm-pin-600 && \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            rocm-hip-runtime \
            rocblas \
            miopen-hip \
            rocrand; \
    fi && \
    rm -rf /var/lib/{dpkg,cache,log}/
COPY --from=builder /build/target/release/stemgen /usr/bin/stemgen
COPY --from=builder /build/target/release/libonnxruntime_providers*.so /usr/bin
ENV LD_LIBRARY_PATH=/usr/local/cuda/targets/x86_64-linux/lib/:/opt/rocm/lib/
RUN useradd -m -u 1000 user
USER user
RUN mkdir -p /home/user/.cache/dev.acolombier.stemgen
VOLUME /home/user/.cache/dev.acolombier.stemgen
ENTRYPOINT [ "/usr/bin/stemgen" ]
