# syntax=docker/dockerfile:1
# base.Dockerfile — Ubuntu 26.04 + core tools + Caddy + s6-overlay
# Supports: linux/amd64, linux/arm64

ARG UBUNTU_VERSION=26.04
ARG S6_OVERLAY_VERSION=3.2.3.0

FROM caddy:2-alpine AS caddy-bin

FROM ubuntu:${UBUNTU_VERSION}

ARG S6_OVERLAY_VERSION
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=UTC

# Core OS packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash zsh tmux neovim git curl wget ca-certificates gnupg \
    openssh-client locales tzdata sudo xz-utils unzip zip \
    jq ripgrep fd-find fzf bat eza tree less \
    direnv zoxide shellcheck shfmt \
    htop ncdu lsof procps psmisc iproute2 iputils-ping \
    dnsutils netcat-openbsd socat \
    make pkg-config \
    && locale-gen en_US.UTF-8 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Build-time CA certificates (for enterprise/corporate laptop builds).
# Place .crt files in build-ca-certs/ — they are gitignored by default.
COPY build-ca-certs/ /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Ensure tools with embedded TLS stacks use system certs.
# UV_TOOL_BIN_DIR/UV_TOOL_DIR put uv tool shims in system-wide paths.
ENV UV_SYSTEM_CERTS=true \
    NODE_USE_SYSTEM_CA=1 \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/opt/uv-tools/bin

# Symlink fd and bat to standard names
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# Arch mapping — computed once from TARGETARCH, sourced by downstream RUNs.
# Only generic/reusable patterns live here. Tool-specific quirks belong in their Dockerfiles.
# MUSL_ARCH:  x86_64-unknown-linux-musl / aarch64-unknown-linux-musl  (xh, delta, hyperfine)
# GNU_ARCH:   x86_64 / aarch64                                        (s6-overlay, lazygit)
RUN <<EOF
set -eu
case "${TARGETARCH}" in
  amd64) printf 'MUSL_ARCH=x86_64-unknown-linux-musl\nGNU_ARCH=x86_64\n' ;;
  arm64) printf 'MUSL_ARCH=aarch64-unknown-linux-musl\nGNU_ARCH=aarch64\n' ;;
  *) echo "Unsupported arch: ${TARGETARCH}" >&2; exit 1 ;;
esac > /etc/arch-env
EOF

# s6-overlay
RUN . /etc/arch-env \
    && curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 --remove-on-error \
       "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
       -o /tmp/s6-noarch.tar.xz \
    && curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 --remove-on-error \
       "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${GNU_ARCH}.tar.xz" \
       -o /tmp/s6-arch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-arch.tar.xz \
    && rm /tmp/s6-noarch.tar.xz /tmp/s6-arch.tar.xz

# Caddy
COPY --from=caddy-bin /usr/bin/caddy /usr/bin/caddy

# Starship prompt
RUN curl -fsSL https://starship.rs/install.sh | sh -s -- --yes \
    && starship --version

# Create dev user (Ubuntu 26.04 ships with an 'ubuntu' user at UID/GID 1000)
ARG DEV_UID=1000
ARG DEV_GID=1000
RUN userdel -r ubuntu 2>/dev/null || true \
    && groupdel ubuntu 2>/dev/null || true \
    && groupadd -g ${DEV_GID} dev \
    && useradd -m -u ${DEV_UID} -g dev -s /bin/zsh dev \
    && echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev

# Runtime and shared tool directories
RUN mkdir -p /workspace /cache /secrets /opt/uv-tools/bin /opt/sdkman \
    && chown -R dev:dev /workspace /cache /opt/uv-tools /opt/sdkman

ENV S6_KEEP_ENV=1 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    ENABLE_CODE=false \
    ENABLE_JUPYTER=false

EXPOSE 8080
WORKDIR /workspace
ENTRYPOINT ["/init"]
