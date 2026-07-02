# syntax=docker/dockerfile:1
# platform.Dockerfile — polyglot + Kubernetes/cloud/API/DB tooling
# All binary downloads are multi-arch (amd64/arm64).

ARG BASE_IMAGE=ghcr.io/jcube/workspace:polyglot
FROM ${BASE_IMAGE}

ARG TARGETARCH

# Pinned versions
ARG KUBECTL_VERSION=v1.36.2
ARG HELM_VERSION=v4.2.2
ARG K9S_VERSION=v0.51.0
ARG STERN_VERSION=1.34.0
ARG KUBECTX_VERSION=v0.11.0
ARG XH_VERSION=0.26.1
ARG GRPCURL_VERSION=1.9.3
ARG LAZYGIT_VERSION=0.62.2
ARG DELTA_VERSION=0.19.2
ARG DUCKDB_VERSION=1.5.4
ARG GRON_VERSION=0.7.1
ARG WEBSOCAT_VERSION=1.14.1
ARG S5CMD_VERSION=2.3.0
ARG MC_VERSION=RELEASE.2025-08-13T08-35-41Z

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Tool-specific arch mapping (appended to /etc/arch-env from base)
RUN <<EOF
set -eu
case "${TARGETARCH}" in
  amd64) printf 'GRPCURL_ARCH=x86_64\nLAZYGIT_ARCH=x86_64\nDUCKDB_ARCH=amd64\nS5CMD_ARCH=64bit\n' ;;
  arm64) printf 'GRPCURL_ARCH=arm64\nLAZYGIT_ARCH=arm64\nDUCKDB_ARCH=arm64\nS5CMD_ARCH=arm64\n' ;;
esac >> /etc/arch-env
EOF

# Database clients
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      postgresql-client redis-tools kcat miller rsync rocksdb-tools \
      datamash pv parallel gawk \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# websocat
RUN set -eux; \
    source /etc/arch-env; \
    curl -fsSL "https://github.com/vi/websocat/releases/download/v${WEBSOCAT_VERSION}/websocat.${MUSL_ARCH}" \
      -o /usr/local/bin/websocat; \
    chmod +x /usr/local/bin/websocat

# kubectl + helm
RUN set -eux; \
    curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl"; \
    chmod +x /usr/local/bin/kubectl; \
    curl -fsSL \
      "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" \
      | tar -xz -C /tmp; \
    mv "/tmp/linux-${TARGETARCH}/helm" /usr/local/bin/helm; \
    chmod +x /usr/local/bin/helm; \
    rm -rf "/tmp/linux-${TARGETARCH}"

# k9s + stern + kubectx/kubens
RUN set -eux; \
    curl -fsSL \
      "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${TARGETARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin k9s; \
    curl -fsSL \
      "https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_${TARGETARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin stern; \
    curl -fsSLo /usr/local/bin/kubectx \
      "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubectx"; \
    curl -fsSLo /usr/local/bin/kubens \
      "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubens"; \
    chmod +x /usr/local/bin/kubectx /usr/local/bin/kubens

# xh
RUN set -eux; \
    source /etc/arch-env; \
    curl -fsSL "https://github.com/ducaale/xh/releases/download/v${XH_VERSION}/xh-v${XH_VERSION}-${MUSL_ARCH}.tar.gz" \
      | tar -C /usr/local/bin --strip-components=1 -xz --wildcards "*/xh"

# grpcurl
RUN set -eux; \
    source /etc/arch-env; \
    curl -fsSL \
      "https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}/grpcurl_${GRPCURL_VERSION}_linux_${GRPCURL_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin grpcurl

# lazygit
RUN set -eux; \
    source /etc/arch-env; \
    curl -fsSL \
      "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_linux_${LAZYGIT_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin lazygit

# delta
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
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# just (install script is arch-aware)
RUN curl -fsSL https://just.systems/install.sh | bash -s -- --to /usr/local/bin

# DuckDB
RUN set -eux; \
    source /etc/arch-env; \
    curl -fsSLo /tmp/duckdb.zip \
      "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-${DUCKDB_ARCH}.zip"; \
    unzip -q /tmp/duckdb.zip -d /usr/local/bin; \
    chmod +x /usr/local/bin/duckdb; \
    rm /tmp/duckdb.zip

# yq (TARGETARCH works directly)
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${TARGETARCH}" \
    -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# gron (TARGETARCH works directly)
RUN curl -fsSL \
    "https://github.com/tomnomnom/gron/releases/download/v${GRON_VERSION}/gron-linux-${TARGETARCH}-${GRON_VERSION}.tgz" \
    | tar -xz -C /usr/local/bin gron && chmod +x /usr/local/bin/gron

# S3/object-storage clients
RUN set -eux; \
    source /etc/arch-env; \
    curl -fsSL "https://github.com/peak/s5cmd/releases/download/v${S5CMD_VERSION}/s5cmd_${S5CMD_VERSION}_Linux-${S5CMD_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin s5cmd; \
    curl -fsSL "https://dl.min.io/client/mc/release/linux-${TARGETARCH}/archive/mc.${MC_VERSION}" \
      -o /usr/local/bin/mc; \
    chmod +x /usr/local/bin/s5cmd /usr/local/bin/mc

# httpie (Python — arch-independent)
USER dev
RUN --mount=type=cache,target=/cache/uv,sharing=locked,uid=1000,gid=1000 \
    uv tool install httpie
USER root
