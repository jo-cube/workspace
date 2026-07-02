# syntax=docker/dockerfile:1.7
# Enterprise workspace overlay
# Builds FROM the generic workspace image and adds enterprise-specific config.

ARG BASE_IMAGE=ghcr.io/jcube/workspace:polyglot
FROM ${BASE_IMAGE}

# Enterprise CA certificates
COPY config/ca-certificates/ /usr/local/share/ca-certificates/enterprise/
RUN update-ca-certificates

# Optional: Homebrew for enterprise-only tools
ARG ENABLE_HOMEBREW=false
RUN if [ "$ENABLE_HOMEBREW" = "true" ]; then \
      NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      && echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/dev/.zshrc \
      && echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/dev/.bashrc \
      && chown dev:dev /home/dev/.zshrc /home/dev/.bashrc; \
    fi

# Optional: install Brewfile packages
COPY config/Brewfile /tmp/Brewfile
RUN if [ "$ENABLE_HOMEBREW" = "true" ] && [ -f /tmp/Brewfile ]; then \
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" \
      && brew bundle --file=/tmp/Brewfile --no-lock; \
    fi \
    && rm -f /tmp/Brewfile

# Proxy environment (sourced by shells and tools)
COPY config/proxy.env /etc/enterprise/proxy.env
RUN printf '%s\n' \
      '[ -r /etc/enterprise/proxy.env ] || return 0' \
      'set -a' \
      '. /etc/enterprise/proxy.env' \
      'set +a' \
      > /etc/profile.d/enterprise-proxy.sh

# Git enterprise defaults
COPY config/git/gitconfig /etc/gitconfig

# Enterprise package registry configuration (npm, pip, maven, etc.)
COPY config/registry/ /etc/enterprise/registry/
