# Architecture

## Design principles

- One Dockerfile per flavor for readability and independent iteration
- Each flavor builds FROM the previous layer's image
- Runtime config is applied as a final overlay for fast service config rebuilds
- s6-overlay supervises long-running services (Caddy, code-server, Jupyter)
- Caddy provides a single-port reverse proxy with path-based routing
- Browser app authentication stays inside code-server and JupyterLab
- Image flavors own service defaults; runtime env only supplies app config and auth
- Images install tools at build time; releases are smoke-tested, scanned, and attested
- Volumes preserve state across container restarts

## Image hierarchy

```
ubuntu:26.04
└── base-core: base.Dockerfile (core tools, Caddy, s6-overlay, dev user)
    └── code.Dockerfile (code-server)
        ├── python.Dockerfile (uv, Python 3.14)
        ├── jvm.Dockerfile (Java 25, Kotlin, Gradle)
        └── polyglot.Dockerfile (Python + JVM + Go + Rust + Node.js)
            ├── lab.Dockerfile (JupyterLab)
            ├── platform.Dockerfile (kubectl, helm, k9s, API/DB clients)
            └── full.Dockerfile (platform + lab + debug + security)
                └── runtime.Dockerfile (status API, s6, Caddy, dotfiles, scripts)
```

Each tool Dockerfile is self-contained and references its parent via `ARG BASE_IMAGE`. The `docker-bake.hcl` wires internal `*-core` targets and publishes flavor tags through `runtime.Dockerfile`.

## Runtime filesystem

```
/workspace      User projects (bind mount)
/home/dev       Dev user home (named volume, seeded once)
/cache          Package/tool caches (named volume)
/etc/workspace  Optional app config (read-only bind mount)
/srv            Static assets (index page)
```

Managed image configuration lives under `/etc`, `/usr/local`, and `/srv` and
follows image updates. Defaults copied into `/home/dev` are initial user state:
they are seeded only when the home volume is empty and are not managed after
that.

## Service supervision

s6-overlay starts all registered services. Each service checks its image-provided `ENABLE_*` environment variable and idles if disabled.

```
/etc/s6-overlay/s6-rc.d/
├── user/              bundle: declares which services to start
│   └── contents.d/
│       ├── caddy
│       ├── code-server
│       ├── jupyter
│       └── workspace-status
├── caddy/             reverse proxy
├── code-server/       browser IDE
├── jupyter/           notebook server
└── workspace-status/  health/introspection API
```

## Network model

```
                      ┌─────────────────────────┐
  Browser ──► :8080 ──►│        Caddy            │
                      │  (path-based routing)   │
                      └──┬───────┬───────┬──────┘
                         │       │       │
              /code      │ /lab  │ /status│  /
              ┌──────────▼┐ ┌───▼────┐ ┌─▼────────┐
              │code-server│ │Jupyter │ │workspace │
              │  :8081    │ │ :8888  │ │-status   │
              └───────────┘ └────────┘ │  :8082   │
                                       └──────────┘
```

All internal services bind to 127.0.0.1. Caddy listens on the container's port
8080, which Compose publishes to host loopback by default. A deployment may
opt into another host bind address, but passwordless use is intended only for a
trusted single-user loopback boundary or an authenticated workspace proxy.
code-server and JupyterLab own browser login state when configured.

Routes:
- `/` — static dashboard (shows services, system info, links)
- `/code`, `/code/*` — code-server (path prefix stripped)
- `/lab`, `/lab/*` — JupyterLab
- `/health`, `/ready`, `/status`, `/status/*` — workspace-status API. `/status` reports service state, not raw feature-flag environment.

Requests to an unavailable app receive Caddy's normal upstream error response.

## Build system

- `docker/*.Dockerfile` — one file per flavor, easy to read and modify independently
- `docker-bake.hcl` — defines `*-core` tool targets plus public runtime-overlay targets
- `compose.yaml` — local development with `FLAVOR` image selection
- `justfile` — thin wrapper around bake and compose for local workflows
