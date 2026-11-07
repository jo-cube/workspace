# syntax=docker/dockerfile:1
# platform.Dockerfile — polyglot + Kubernetes/cloud/API/DB tooling
# All binary downloads are multi-arch (amd64/arm64).

ARG BASE_IMAGE

FROM pgsty/mc:RELEASE.2026-10-26T00-00-00Z@sha256:ce62c9053c69ce12a527a322345b5ad9f44b5f8a7b8189f82e516f2e3f30f1d8 AS mc-bin

FROM ${BASE_IMAGE}

ARG TARGETARCH

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Tool-specific arch mapping (appended to /etc/arch-env from base)
RUN <<EOF
set -eu
case "${TARGETARCH}" in
  amd64) printf 'LAZYGIT_ARCH=x86_64\n' ;;
  arm64) printf 'LAZYGIT_ARCH=arm64\n' ;;
esac >> /etc/arch-env
EOF

# Database clients
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      postgresql-client redis-tools kcat miller rsync rocksdb-tools \
      datamash pv parallel gawk

# Build Go tools with the image toolchain so standard-library security fixes apply.
ARG GRON_VERSION=0.7.1
ARG S5CMD_VERSION=2.3.0
ARG GRPCURL_VERSION=1.9.4
# grpcurl 1.9.4 still requires x/net v0.58.0, affected by GO-2026-6610.
# Remove this override when an upstream release includes the HTTP/2 fixes.
ARG GRPCURL_NET_VERSION=v0.62.0
RUN --mount=type=cache,target=/cache/go/pkg/mod,sharing=locked \
    --mount=type=cache,target=/home/dev/.cache/go-build,sharing=locked \
    set -eux; \
    GOBIN=/usr/local/bin go install github.com/tomnomnom/gron@v${GRON_VERSION}; \
    GOBIN=/usr/local/bin go install github.com/peak/s5cmd/v2@v${S5CMD_VERSION}; \
    mkdir /tmp/grpcurl-build; \
    cd /tmp/grpcurl-build; \
    go mod init workspace-grpcurl-build; \
    go get github.com/fullstorydev/grpcurl/cmd/grpcurl@v${GRPCURL_VERSION}; \
    go get golang.org/x/net@${GRPCURL_NET_VERSION}; \
    GOBIN=/usr/local/bin go install -mod=mod github.com/fullstorydev/grpcurl/cmd/grpcurl; \
    rm -rf /tmp/grpcurl-build

# Maintained MinIO client fork; keep the existing command and ~/.mc configuration.
COPY --from=mc-bin /usr/bin/mc /usr/local/bin/mc

# websocat
ARG WEBSOCAT_VERSION=1.14.1
RUN set -eux; \
    source /etc/arch-env; \
    curl -fsSL "https://github.com/vi/websocat/releases/download/v${WEBSOCAT_VERSION}/websocat.${MUSL_ARCH}" \
      -o /usr/local/bin/websocat; \
    chmod +x /usr/local/bin/websocat

# kubectl + helm
ARG KUBECTL_VERSION=v1.37.2
ARG HELM_VERSION=v4.3.1
RUN set -eux; \
    cd /tmp; \
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 --remove-on-error \
      -o kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl"; \
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 --remove-on-error \
      -o kubectl.sha256 "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256"; \
    printf '%s  kubectl\n' "$(cat kubectl.sha256)" | sha256sum --check; \
    install -m 0755 kubectl /usr/local/bin/kubectl; \
    archive="helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz"; \
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 --remove-on-error \
      -o "$archive" "https://get.helm.sh/${archive}"; \
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 --remove-on-error \
      -o "${archive}.sha256sum" "https://get.helm.sh/${archive}.sha256sum"; \
    sha256sum --check "${archive}.sha256sum"; \
    tar -xzf "$archive"; \
    install -m 0755 "linux-${TARGETARCH}/helm" /usr/local/bin/helm; \
    rm -rf kubectl kubectl.sha256 "$archive" "${archive}.sha256sum" "linux-${TARGETARCH}"

# k9s + stern + kubectx/kubens
ARG K9S_VERSION=v0.51.0
ARG STERN_VERSION=1.35.0
ARG KUBECTX_VERSION=v0.11.0
RUN set -eux; \
    cd /tmp; \
    archive="k9s_Linux_${TARGETARCH}.tar.gz"; \
    curl -fsSLo "$archive" \
      "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/${archive}"; \
    curl -fsSLo k9s-checksums.sha256 \
      "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/checksums.sha256"; \
    awk -v archive="$archive" '$2 == archive' k9s-checksums.sha256 | sha256sum --check; \
    tar -xz -C /usr/local/bin -f "$archive" k9s; \
    rm "$archive" k9s-checksums.sha256; \
    archive="stern_${STERN_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    curl -fsSLo "$archive" \
      "https://github.com/stern/stern/releases/download/v${STERN_VERSION}/${archive}"; \
    curl -fsSLo stern-checksums.txt \
      "https://github.com/stern/stern/releases/download/v${STERN_VERSION}/checksums.txt"; \
    awk -v archive="$archive" '$2 == archive' stern-checksums.txt | sha256sum --check; \
    tar -xz -C /usr/local/bin -f "$archive" stern; \
    rm "$archive" stern-checksums.txt; \
    curl -fsSLo /usr/local/bin/kubectx \
      "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubectx"; \
    curl -fsSLo /usr/local/bin/kubens \
      "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubens"; \
    chmod +x /usr/local/bin/kubectx /usr/local/bin/kubens

# xh
ARG XH_VERSION=0.26.3
RUN set -eux; \
    source /etc/arch-env; \
    curl -fsSL "https://github.com/ducaale/xh/releases/download/v${XH_VERSION}/xh-v${XH_VERSION}-${MUSL_ARCH}.tar.gz" \
      | tar -C /usr/local/bin --strip-components=1 -xz --wildcards "*/xh"

# lazygit
ARG LAZYGIT_VERSION=0.66.2
RUN set -eux; \
    source /etc/arch-env; \
    cd /tmp; \
    archive="lazygit_${LAZYGIT_VERSION}_linux_${LAZYGIT_ARCH}.tar.gz"; \
    curl -fsSLo "$archive" \
      "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/${archive}"; \
    curl -fsSLo lazygit-checksums.txt \
      "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/checksums.txt"; \
    awk -v archive="$archive" '$2 == archive' lazygit-checksums.txt | sha256sum --check; \
    tar -xz -C /usr/local/bin -f "$archive" lazygit; \
    rm "$archive" lazygit-checksums.txt

# delta
ARG DELTA_VERSION=0.20.1
RUN set -eux; \
    source /etc/arch-env; \
    curl -fsSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-${GNU_ARCH}-unknown-linux-gnu.tar.gz" \
      | tar -C /usr/local/bin --strip-components=1 -xz --wildcards "*/delta"

# gh CLI (apt handles arch natively)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh

# just (install script is arch-aware)
RUN curl -fsSL https://just.systems/install.sh | bash -s -- --to /usr/local/bin \
    && just --version

# DuckDB (SHA256 digests published with the v2.0.0 release assets)
ARG DUCKDB_VERSION=2.0.0
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) checksum=c6507206baf7793c6013dbd82368469a45f20dc0e17a6f92f204602f652ed2bc ;; \
      arm64) checksum=859e1875d2a9515fbb4bf8871061437a14af82320da68c753f094c4b776348fe ;; \
    esac; \
    cd /tmp; \
    archive="duckdb-cli-linux-${TARGETARCH}.tar.gz"; \
    curl -fsSLo "$archive" \
      "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/${archive}"; \
    printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check; \
    tar -xz -C /usr/local/bin -f "$archive" duckdb; \
    rm "$archive"

# yq (TARGETARCH works directly)
ARG YQ_VERSION=v4.54.2
RUN set -eux; \
    cd /tmp; \
    curl -fsSLo "yq_linux_${TARGETARCH}" \
      "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${TARGETARCH}"; \
    curl -fsSLo yq-checksums-bsd \
      "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/checksums-bsd"; \
    grep -F "SHA256 (yq_linux_${TARGETARCH}) = " yq-checksums-bsd | sha256sum --check; \
    install -m 0755 "yq_linux_${TARGETARCH}" /usr/local/bin/yq; \
    rm "yq_linux_${TARGETARCH}" yq-checksums-bsd; \
    yq --version
