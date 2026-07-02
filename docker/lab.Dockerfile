# syntax=docker/dockerfile:1
# lab.Dockerfile — polyglot + JupyterLab

ARG BASE_IMAGE=ghcr.io/jo-cube/workspace:polyglot
FROM ${BASE_IMAGE}

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
