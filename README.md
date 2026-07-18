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
`/home/dev` is user state: shell history, config, and caches. Image-provided
dotfiles seed a new home volume once; later image updates do not overwrite user
changes.

## Optional auth

Compose binds to `127.0.0.1` by default, so code-server and JupyterLab can run
without app-level auth for trusted single-user local use. To enable password or
token protection, set environment variables in `.env` or in
`runtime-config/config.env`:

```bash
PASSWORD='change-me'
JUPYTER_TOKEN='change-me-too'
```

Use `HASHED_PASSWORD` instead of `PASSWORD` when you already have a code-server
password hash. Caddy only routes traffic; code-server and JupyterLab own their
login behavior. `runtime-config/` is mounted read-only at `/etc/workspace`; its
contents are excluded from both Git and the Docker build context.

To listen beyond loopback, set `WORKSPACE_BIND_ADDRESS=0.0.0.0`. Do that only
behind an authenticated workspace proxy such as Coder, or after configuring
app-level credentials and an appropriate network/TLS boundary.

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
- Keep managed service and shell config in the final runtime overlay so rebuilds stay quick.
- Keep local credentials in the read-only `runtime-config/` mount; changing them does not require a rebuild.
- Treat `/home/dev` defaults as copy-once user state. Use managed `/etc` config for settings that must follow image updates.
- Do not prune Docker build cache casually. It is useful state.
- Keep build logs gated: redirect noisy logs to `/tmp/...` and show only a short tail on failure.
- Add tests only when they freeze useful behavior or catch real regressions.
- Clean up test containers and volumes; leave needed images and build cache in place.
- Avoid bloat. Prefer distro packages, static binaries, standard tooling, and deletion over custom machinery.

## Requirements

- Docker with BuildKit/buildx
- Docker Compose v2
- [`just`](https://just.systems)

## More docs

- [Image flavors](docs/images.md)
- [Local development](docs/local-development.md)
- [Tool manifest](docs/tools.md)
- [Architecture](docs/architecture.md)
- [Coder integration](docs/coder.md)
- [Releasing](docs/releasing.md)
