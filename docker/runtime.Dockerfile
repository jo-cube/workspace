# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ubuntu:26.04

FROM golang:1.26-alpine AS status-build
WORKDIR /src
COPY services/status/go.mod .
COPY services/status/main.go .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /workspace-status .

FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/jo-cube/workspace" \
      org.opencontainers.image.description="Containerized development workspace images"

ENV STARSHIP_CONFIG=/etc/starship.toml \
    PYTHONDONTWRITEBYTECODE=1

RUN rm -rf \
      /etc/s6-overlay/s6-rc.d/caddy \
      /etc/s6-overlay/s6-rc.d/code-server \
      /etc/s6-overlay/s6-rc.d/fix-perms \
      /etc/s6-overlay/s6-rc.d/jupyter \
      /etc/s6-overlay/s6-rc.d/workspace-status \
    && rm -f \
      /etc/s6-overlay/s6-rc.d/user/contents.d/caddy \
      /etc/s6-overlay/s6-rc.d/user/contents.d/code-server \
      /etc/s6-overlay/s6-rc.d/user/contents.d/fix-perms \
      /etc/s6-overlay/s6-rc.d/user/contents.d/jupyter \
      /etc/s6-overlay/s6-rc.d/user/contents.d/workspace-status

COPY config/s6/ /etc/s6-overlay/s6-rc.d/
RUN chmod +x /etc/s6-overlay/s6-rc.d/caddy/run \
    /etc/s6-overlay/s6-rc.d/code-server/run \
    /etc/s6-overlay/s6-rc.d/jupyter/run \
    /etc/s6-overlay/s6-rc.d/workspace-status/run

COPY config/cont-init.d/ /etc/cont-init.d/
RUN chmod +x /etc/cont-init.d/*

COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

RUN rm -f /etc/caddy/Caddyfile
COPY config/caddy.json /etc/caddy/caddy.json
COPY config/index.html /srv/index.html
COPY config/profile.d/workspace.sh /etc/profile.d/workspace.sh
COPY config/starship.toml /etc/starship.toml
COPY config/zsh/zshrc /etc/zsh/zshrc
COPY --from=status-build /workspace-status /usr/local/bin/workspace-status

COPY --chown=dev:dev config/dotfiles/ /home/dev/

EXPOSE 8080
WORKDIR /workspace
ENTRYPOINT ["/init"]
