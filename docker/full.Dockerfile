# syntax=docker/dockerfile:1
# full.Dockerfile — platform + lab + debug + security tools
# All binary downloads are multi-arch (amd64/arm64).

ARG BASE_IMAGE=ghcr.io/jcube/workspace:platform
FROM ${BASE_IMAGE}

ARG TARGETARCH

# Pinned versions
ARG GITLEAKS_VERSION=8.30.1
ARG HYPERFINE_VERSION=1.20.0
ARG TRIVY_VERSION=0.71.2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Tool-specific arch mapping (appended to /etc/arch-env from base/platform)
RUN <<EOF
set -eu
case "${TARGETARCH}" in
  amd64) printf 'GITLEAKS_ARCH=x64\nTRIVY_ARCH=64bit\n' ;;
  arm64) printf 'GITLEAKS_ARCH=arm64\nTRIVY_ARCH=ARM64\n' ;;
esac >> /etc/arch-env
EOF

# JupyterLab
USER dev
RUN --mount=type=cache,target=/cache/uv,sharing=locked,uid=1000,gid=1000 \
    --mount=type=cache,target=/opt/rust/cargo/registry,sharing=locked,uid=1000,gid=1000 \
    uv tool install jupyterlab \
      --with bash_kernel \
      --with kotlin-jupyter-kernel \
  && /opt/uv-tools/jupyterlab/bin/python -m bash_kernel.install --sys-prefix \
  && /opt/uv-tools/jupyterlab/bin/python -c 'import json,pathlib,sys; p=pathlib.Path(sys.prefix)/"share/jupyter/kernels/kotlin/kernel.json"; data=json.loads(p.read_text()); data["argv"][0]=sys.executable; data["metadata"]["jar_path_detect_command"][0]=sys.executable; p.write_text(json.dumps(data, indent=2)+"\n")' \
  && rustup component add rust-src \
  && cargo install --locked evcxr_jupyter \
  && JUPYTER_PATH=/opt/uv-tools/jupyterlab/share/jupyter evcxr_jupyter --install \
  && uv tool update-shell \
  && uv venv

USER root
RUN --mount=type=cache,target=/cache/go/pkg/mod,sharing=locked \
    --mount=type=cache,target=/home/dev/.cache/go-build,sharing=locked,uid=1000,gid=1000 \
    set -eux; \
    GOBIN=/usr/local/bin go install github.com/janpfeifer/gonb@latest; \
    GOBIN=/usr/local/bin go install golang.org/x/tools/cmd/goimports@latest; \
    GOBIN=/usr/local/bin go install golang.org/x/tools/gopls@latest; \
    HOME=/tmp/gonb-home gonb --install; \
    kernel_dir=/opt/uv-tools/jupyterlab/share/jupyter/kernels/gonb; \
    mkdir -p "$kernel_dir"; \
    cp -a /tmp/gonb-home/.local/share/jupyter/kernels/gonb/. "$kernel_dir/"; \
    rm -rf /tmp/gonb-home; \
    chown -R dev:dev "$kernel_dir"
ENV ENABLE_JUPYTER=true

# Debug/system tools
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      gdb strace ltrace valgrind tcpdump sqlite3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# trivy
RUN set -eux; \
    source /etc/arch-env; \
    curl -fsSL \
      "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin trivy

# gitleaks
RUN set -eux; \
    source /etc/arch-env; \
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz" \
      | tar -C /usr/local/bin -xz gitleaks

# hyperfine
RUN set -eux; \
    source /etc/arch-env; \
    curl -fsSL "https://github.com/sharkdp/hyperfine/releases/download/v${HYPERFINE_VERSION}/hyperfine-v${HYPERFINE_VERSION}-${GNU_ARCH}-unknown-linux-gnu.tar.gz" \
      | tar -C /usr/local/bin --strip-components=1 -xz --wildcards "*/hyperfine"
