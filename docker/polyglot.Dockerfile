# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG TARGETARCH
ARG GO_VERSION=1.26.4

ENV UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/opt/uv-tools/bin \
    UV_CACHE_DIR=/cache/uv \
    XDG_DATA_HOME=/home/dev/.local/share \
    XDG_CACHE_HOME=/home/dev/.cache \
    XDG_BIN_HOME=/home/dev/.local/bin \
    GOPATH=/cache/go \
    GRADLE_USER_HOME=/cache/gradle \
    RUSTUP_HOME=/opt/rust/rustup \
    CARGO_HOME=/opt/rust/cargo \
    SDKMAN_DIR=/opt/sdkman \
    FNM_DIR=/opt/fnm

RUN mkdir -p /opt/uv-tools/bin /cache/uv /cache/go /cache/gradle /opt/rust /opt/sdkman /opt/fnm \
    && chown -R dev:dev /opt/uv-tools /cache /opt/rust /opt/sdkman /opt/fnm

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      gcc libc6-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Go
RUN --mount=type=cache,target=/cache/go-downloads,sharing=locked \
    set -eux; \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" \
      -o "/cache/go-downloads/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz"; \
    rm -rf /usr/local/go; \
    tar -C /usr/local -xzf "/cache/go-downloads/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz"

# Python via uv
RUN mkdir -p /opt/uv-python && chown dev:dev /opt/uv-python
USER dev
ENV PATH="/opt/uv-tools/bin:${PATH}" \
    UV_PYTHON_INSTALL_DIR=/opt/uv-python \
    UV_PYTHON_BIN_DIR=/opt/uv-tools/bin
RUN --mount=type=cache,target=/cache/uv,sharing=locked,uid=1000,gid=1000 \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/opt/uv-tools/bin UV_NO_MODIFY_PATH=1 sh \
    && uv python install 3.14 --default \
    && uv tool install ipython \
    && uv tool install ruff \
    && uv tool install mypy

# JVM via SDKMAN
RUN --mount=type=cache,target=/opt/sdkman/archives,sharing=locked \
    curl -s "https://get.sdkman.io" | bash \
    && bash -lc 'source "$SDKMAN_DIR/bin/sdkman-init.sh" \
    && sdk install java 25.0.3-tem \
    && sdk install kotlin \
    && sdk install gradle' \
    && rm -rf "$SDKMAN_DIR/tmp"/*

# Rust
RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable --no-modify-path \
    && "$CARGO_HOME/bin/rustup" component add clippy rustfmt

# Node.js via fnm
RUN curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir /opt/fnm --skip-shell \
    && /opt/fnm/fnm install 24

ENV PATH="/usr/local/go/bin:${SDKMAN_DIR}/candidates/java/current/bin:${SDKMAN_DIR}/candidates/kotlin/current/bin:${SDKMAN_DIR}/candidates/gradle/current/bin:${CARGO_HOME}/bin:${FNM_DIR}/aliases/default/bin:${FNM_DIR}:${PATH}" \
    JAVA_HOME="${SDKMAN_DIR}/candidates/java/current"

USER root
