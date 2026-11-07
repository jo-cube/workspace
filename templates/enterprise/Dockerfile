# syntax=docker/dockerfile:1.7
# Enterprise workspace overlay
# Builds FROM the generic workspace image and adds enterprise-specific config.

ARG BASE_IMAGE=ghcr.io/jo-cube/workspace:platform-latest
FROM ${BASE_IMAGE}

# Enterprise CA certificates
COPY config/ca-certificates/ /usr/local/share/ca-certificates/enterprise/
RUN update-ca-certificates

# Proxy environment: login shells use profile/zprofile; interactive non-login shells use rc files.
COPY config/proxy.env /etc/enterprise/proxy.env
RUN printf '%s\n' \
      '[ -r /etc/enterprise/proxy.env ] || return 0' \
      'set -a' \
      '. /etc/enterprise/proxy.env' \
      'set +a' \
      > /etc/profile.d/enterprise-proxy.sh \
    && printf '\n%s\n' 'shopt -q login_shell || . /etc/profile.d/enterprise-proxy.sh' >> /etc/bash.bashrc \
    && printf '\n%s\n' '. /etc/profile.d/enterprise-proxy.sh' >> /etc/zsh/zprofile \
    && printf '\n%s\n' '[[ -o login ]] || . /etc/profile.d/enterprise-proxy.sh' >> /etc/zsh/zshrc

# Git enterprise defaults
COPY config/git/gitconfig /etc/gitconfig

# Enterprise package registry configuration (npm, pip, maven, etc.)
COPY config/registry/ /etc/enterprise/registry/
