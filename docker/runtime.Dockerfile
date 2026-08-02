# syntax=docker/dockerfile:1

ARG BASE_IMAGE

FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/jo-cube/workspace" \
      org.opencontainers.image.description="Containerized development workspace images"

ENV STARSHIP_CONFIG=/etc/starship.toml \
    PYTHONDONTWRITEBYTECODE=1

COPY config/s6/ /etc/s6-overlay/s6-rc.d/
RUN chmod +x /etc/s6-overlay/s6-rc.d/caddy/run \
    /etc/s6-overlay/s6-rc.d/code-server/run \
    /etc/s6-overlay/s6-rc.d/jupyter/run

COPY config/cont-init.d/ /etc/cont-init.d/
RUN chmod +x /etc/cont-init.d/*

COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

COPY config/Caddyfile /etc/caddy/Caddyfile
COPY config/index.html /srv/index.html
COPY config/profile.d/workspace.sh /etc/profile.d/workspace.sh
COPY config/starship.toml /etc/starship.toml
COPY config/zsh/zshrc /etc/zsh/zshrc
COPY --chown=dev:dev config/dotfiles/ /home/dev/

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["curl", "-fsS", "http://127.0.0.1:8080/health"]
WORKDIR /workspace
ENTRYPOINT ["/init"]
