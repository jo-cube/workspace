# syntax=docker/dockerfile:1.7
# Enterprise workspace overlay
# Builds FROM the generic workspace image and adds enterprise-specific config.

ARG BASE_IMAGE=ghcr.io/jo-cube/workspace:platform
FROM ${BASE_IMAGE}

# Enterprise CA certificates
COPY config/ca-certificates/ /usr/local/share/ca-certificates/enterprise/
RUN update-ca-certificates

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
