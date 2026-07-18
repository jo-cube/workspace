# syntax=docker/dockerfile:1
# code.Dockerfile — base + code-server

ARG BASE_IMAGE=ghcr.io/jo-cube/workspace:base
FROM ${BASE_IMAGE}

ARG CODE_SERVER_VERSION=4.126.0

RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- \
      --method=standalone --prefix=/usr/local --version=${CODE_SERVER_VERSION} \
    && code-server --version \
    && rm -rf /root/.cache/code-server

ENV ENABLE_CODE=true
