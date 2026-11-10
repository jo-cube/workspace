# syntax=docker/dockerfile:1
# full.Dockerfile — platform + lab + debug + security tools
# All binary downloads are multi-arch (amd64/arm64).

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG TARGETARCH

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Tool-specific arch mapping (appended to /etc/arch-env from base/platform)
RUN <<EOF
set -eu
case "${TARGETARCH}" in
  amd64) printf 'TRIVY_ARCH=64bit\n' ;;
  arm64) printf 'TRIVY_ARCH=ARM64\n' ;;
esac >> /etc/arch-env
EOF

USER dev
RUN rustup component add rust-src

# Upstream publishes Linux AMD64 binaries only; releases compile ARM64 natively.
# Install Evcxr before Python packages so changing them does not rebuild the Rust kernel.
ARG EVCXR_VERSION=0.22.0
RUN --mount=type=cache,target=/opt/rust/cargo/registry,sharing=locked,uid=1000,gid=1000 \
    set -eux; \
    case "$TARGETARCH" in \
      amd64) \
        archive="evcxr_jupyter-v${EVCXR_VERSION}-x86_64-unknown-linux-gnu.tar.gz"; \
        curl -fsSL --retry 5 --retry-all-errors --remove-on-error \
          "https://github.com/evcxr/evcxr/releases/download/v${EVCXR_VERSION}/$archive" -o "/tmp/$archive"; \
        printf '%s  %s\n' c4c9ffa198d79e2e21518061567f1661c452c44702a09fcb5123fdcaeda0af7a "/tmp/$archive" | sha256sum --check; \
        tar -xz -C "$CARGO_HOME/bin" --strip-components=1 -f "/tmp/$archive" \
          "evcxr_jupyter-v${EVCXR_VERSION}-x86_64-unknown-linux-gnu/evcxr_jupyter"; \
        rm "/tmp/$archive" \
        ;; \
      arm64) \
        cargo install --locked --jobs 1 evcxr_jupyter --version "$EVCXR_VERSION" \
        ;; \
      *) echo "Unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac

# JupyterLab
RUN --mount=type=cache,target=/cache/uv,sharing=locked,uid=1000,gid=1000 \
    uv tool install jupyterlab==4.6.6 \
      --with jupyter-server==2.21.1 \
      --with ipykernel==7.4.0 \
      --with bash_kernel==0.10.0 \
      --with kotlin-jupyter-kernel==0.19.0.944 \
  && /opt/uv-tools/jupyterlab/bin/python -m bash_kernel.install --sys-prefix \
  && /opt/uv-tools/jupyterlab/bin/python -c 'import json,pathlib,sys; p=pathlib.Path(sys.prefix)/"share/jupyter/kernels/kotlin/kernel.json"; data=json.loads(p.read_text()); data["argv"][0]=sys.executable; data["metadata"]["jar_path_detect_command"][0]=sys.executable; p.write_text(json.dumps(data, indent=2)+"\n")' \
  && JUPYTER_PATH=/opt/uv-tools/jupyterlab/share/jupyter evcxr_jupyter --install

USER root
ARG GONB_VERSION=v0.11.5
ARG GO_TOOLS_VERSION=v0.52.0
ARG GOPLS_VERSION=v0.24.0
RUN --mount=type=cache,target=/cache/go/pkg/mod,sharing=locked \
    --mount=type=cache,target=/home/dev/.cache/go-build,sharing=locked,uid=1000,gid=1000 \
    set -eux; \
    GOBIN=/usr/local/bin go install github.com/janpfeifer/gonb@${GONB_VERSION}; \
    GOBIN=/usr/local/bin go install golang.org/x/tools/cmd/goimports@${GO_TOOLS_VERSION}; \
    GOBIN=/usr/local/bin go install golang.org/x/tools/gopls@${GOPLS_VERSION}; \
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
      gdb strace ltrace valgrind tcpdump sqlite3

# trivy
ARG TRIVY_VERSION=0.76.2
RUN set -eux; \
    source /etc/arch-env; \
    cd /tmp; \
    archive="trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz"; \
    curl -fsSL --http1.1 --retry 5 --retry-all-errors --retry-delay 2 \
      "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${archive}" \
      -o "$archive"; \
    curl -fsSL --http1.1 --retry 5 --retry-all-errors --retry-delay 2 \
      "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_checksums.txt" \
      -o trivy-checksums.txt; \
    awk -v archive="$archive" '$2 == archive' trivy-checksums.txt | sha256sum --check; \
    tar -xzf "$archive" -C /usr/local/bin trivy; \
    rm "$archive" trivy-checksums.txt

# gitleaks
ARG GITLEAKS_VERSION=8.30.1
RUN --mount=type=cache,target=/cache/go/pkg/mod,sharing=locked \
    --mount=type=cache,target=/home/dev/.cache/go-build,sharing=locked \
    GOBIN=/usr/local/bin go install github.com/zricethezav/gitleaks/v8@v${GITLEAKS_VERSION}

# Hyperfine (SHA256 digests published with the v2.0.0 release assets)
ARG HYPERFINE_VERSION=2.0.0
RUN set -eux; \
    source /etc/arch-env; \
    case "$TARGETARCH" in \
      amd64) checksum=ae2beda2ac99c098427e4f755244552daf20e514422889cca6d44421e2d93c87 ;; \
      arm64) checksum=f8244d1e17f8da23ee6b3ae2cdc04a6a185a450f6b74e09bff12e498038fcbc9 ;; \
    esac; \
    cd /tmp; \
    archive="hyperfine-v${HYPERFINE_VERSION}-${GNU_ARCH}-unknown-linux-gnu.tar.gz"; \
    curl -fsSLo "$archive" \
      "https://github.com/sharkdp/hyperfine/releases/download/v${HYPERFINE_VERSION}/${archive}"; \
    printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check; \
    tar -C /usr/local/bin --strip-components=1 -xz -f "$archive" --wildcards "*/hyperfine"; \
    rm "$archive"
