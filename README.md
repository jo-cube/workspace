# Workspace

Containerized development workspace images and an enterprise overlay template.

## Repository structure

| Directory | Purpose |
|-----------|---------|
| [`docker/`](docker/) | Per-flavor Dockerfiles for the generic workspace image family. |
| [`config/`](config/) | Runtime Caddy, s6, shell, dotfile, and dashboard config. |
| [`services/`](services/) | Small helper services built into the runtime overlay. |
| [`scripts/`](scripts/) | Local/runtime validation helpers. |
| [`docs/`](docs/) | Operational docs for the generic workspace images. |
| [`templates/enterprise/`](templates/enterprise/) | Enterprise overlay template for CA, proxy, registry, Git, and internal-tool adaptation. |

The generic image flavors decide which services are available and enabled.
Compose only selects the image, port, volumes, and runtime config/secrets.

## Quick start

```bash
# Start the default flavor, building only if the local image is missing.
just start

# Or choose a flavor.
just start polyglot
just start platform
just start full
```

Open:

- `http://localhost:8080` - workspace dashboard
- `http://localhost:8080/code/` - code-server
- `http://localhost:8080/lab` - JupyterLab in `lab` and `full`

Use `just up <flavor>` when you explicitly want to rebuild and start.
Do not use `docker compose up --build`; builds go through `docker buildx bake`.

## Image flavors

```text
base        Ubuntu 26.04 + core tools + Caddy + s6-overlay
code        + code-server
python      + uv, Python 3.14, ruff, mypy
jvm         + Java 25, Kotlin, Gradle
polyglot    + Python + JVM + Go + Rust + Node.js
lab         + JupyterLab
platform    + kubectl, helm, k9s, DB/Kafka/WS clients, API tools
full        platform + lab + debug + security tools
```

`lab` and `full` include JupyterLab kernels for Python, Bash, Rust via Evcxr,
Go via GoNB, and Kotlin.

`platform` and `full` include practical infrastructure helpers: Kubernetes
tools, HTTP/gRPC/WebSocket clients, PostgreSQL and Redis clients, DuckDB,
Kafka `kcat`, S3-compatible object storage clients (`s5cmd`, `mc`), RocksDB
admin tools, and stream-processing tools.

`/workspace` is the bind-mounted project root.
`/home/dev` is user state: shell history, config, and caches.

## Optional auth

code-server and JupyterLab can run without auth for local-only use. To enable
app-level password/token protection, set environment variables in `.env` or in
`runtime-config/config.env`:

```bash
PASSWORD='change-me'
JUPYTER_TOKEN='change-me-too'
```

Use `HASHED_PASSWORD` instead of `PASSWORD` when you already have a code-server
password hash. Caddy only routes traffic; code-server and JupyterLab own their
login behavior.

## Enterprise overlay

```bash
cd templates/enterprise
just start
```

The enterprise module builds from a generic image and adds non-secret
enterprise configuration. Put real values in the clearly named files under
`templates/enterprise/config/`; keep secrets in `templates/enterprise/secrets/`,
environment variables, CI secrets, or platform secret stores.

## Operational rules

- Prefer `just` and `docker buildx bake`.
- Use `just start <flavor>` to start from a local image, building only if missing.
- Use `just up <flavor>` to rebuild explicitly.
- Keep runtime config in the final runtime overlay so Caddy, s6, dotfiles, and config edits rebuild quickly.
- Do not prune Docker build cache casually. It is useful state.
- Keep build logs gated: redirect noisy logs to `/tmp/...` and show only a short tail on failure.
- Add tests only when they freeze useful behavior or catch real regressions.
- Clean up test containers and volumes; leave needed images and build cache in place.
- Avoid bloat. Prefer distro packages, static binaries, standard tooling, and deletion over custom machinery.

## Requirements

- Docker with BuildKit/buildx
- Docker Compose v2
- [`just`](https://just.systems)
