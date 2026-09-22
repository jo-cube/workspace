# Architecture

## Design

- Heavy tools live in cached internal image layers.
- A shared runtime overlay adds Caddy, s6 services, dotfiles, and validation scripts.
- Caddy provides one browser-facing port with path routing.
- code-server and JupyterLab own authentication.
- `/home/dev` contains persistent user state; image-owned tools live under `/opt` or `/usr/local`.

## Image graph

```text
ubuntu:26.04
└── base-core
    └── code-core
        └── polyglot-core
            └── platform-core
                └── full-core

runtime overlay + code-core     → code
runtime overlay + platform-core → platform
runtime overlay + full-core     → full
```

Only `code`, `platform`, and `full` are supported runtime images. The `*-core`
targets exist solely for build reuse.

## Runtime filesystem

```text
/workspace       user projects (bind mount)
/home/dev        persistent user state (named volume)
/cache           package caches (named volume)
/opt             image-owned runtimes and tools
/etc/workspace   optional app config (read-only bind mount)
/srv             static dashboard
```

An existing `/home/dev` volume is intentionally not reseeded on image updates,
so runtimes must never be installed there.

## Services

s6-overlay supervises:

- Caddy on `:8080`
- code-server on `127.0.0.1:8081`
- JupyterLab on `127.0.0.1:8888` in `full`

Disabled optional services idle without exposing a port.
Docker health status probes Caddy and every service enabled for the selected
image, so a failed browser application cannot leave the container healthy.

## Routes

```text
/                 static service links
/health           static 200 response
/code, /code/*    code-server
/lab, /lab/*      JupyterLab
```

Compose publishes Caddy to host loopback by default. Passwordless operation is
for a trusted single-user loopback boundary or an authenticated workspace
proxy.

## Build system

- `docker/*.Dockerfile` — readable internal layers and the final runtime overlay
- `docker-bake.hcl` — dependency graph for the three supported images
- `compose.yaml` — local launcher
- `justfile` — thin build and runtime commands, including pull and command execution

Bake, Compose, and published releases use `<flavor>-<tag>` image names.
The launchers load `.env`, honor shell overrides, and wait for Docker health
before reporting successful startup. `just health` runs the same probe as
Docker; `/health` checks only Caddy liveness.
