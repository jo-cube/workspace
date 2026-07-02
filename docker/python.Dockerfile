# syntax=docker/dockerfile:1
# python.Dockerfile — code + Python/uv

ARG BASE_IMAGE=ghcr.io/jo-cube/workspace:code
FROM ${BASE_IMAGE}

USER dev

ENV UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/opt/uv-tools/bin \
    UV_CACHE_DIR=/cache/uv

ENV PATH="/opt/uv-tools/bin:${PATH}"
RUN --mount=type=cache,target=/cache/uv,sharing=locked,uid=1000,gid=1000 \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/opt/uv-tools/bin sh \
    && uv python install 3.14 \
    && uv tool install ipython \
    && uv tool install ruff \
    && uv tool install mypy

USER root
