# Workspace

Containerized development workspace images and an enterprise overlay template.

## Repository structure

| Directory | Purpose |
|-----------|---------|
| [`docker/`](docker/) | Internal image layers and the shared runtime overlay. |
| [`config/`](config/) | Runtime Caddy, s6, shell, dotfile, and dashboard config. |
| [`scripts/`](scripts/) | Local/runtime validation helpers. |
| [`docs/`](docs/) | Operational documentation. |
| [`templates/enterprise/`](templates/enterprise/) | Enterprise CA, proxy, registry, Git, and internal-tool overlay. |

## Quick start

```bash
just start           # code
just start platform
just start full

# Use a published image without a local build
just pull platform
just start platform
```

`just start` builds only when the selected local image is missing. Use
`just up <flavor>` to rebuild. Both wait for the proxy and enabled browser
services to be healthy. Builds go through `docker buildx bake`.

Images use `<flavor>-<tag>`, such as `platform-latest`. Set `FLAVOR`, `TAG`, and
`REGISTRY` in `.env` to use the same selection for builds, pulls, and startup;
shell environment values take precedence. For a specific release, set
`TAG=1.3.0`, then run `just pull` and `just start`.

Use `just shell` for an interactive terminal, or `just exec <command> ...` to
run a command as `dev` in `/workspace`, including pipelines:

```bash
just exec git status
printf 'hello\n' | just exec cat
just health          # proxy and enabled services
just status          # container state and Docker health
```

Open:

- `http://localhost:8080` — workspace links
- `http://localhost:8080/code/` — code-server
- `http://localhost:8080/lab` — JupyterLab in `full`
- `http://localhost:8080/health` — proxy liveness

## Supported images

| Image | Contents |
|-------|----------|
| `code` | Ubuntu 26.04, core CLI tools, Caddy, s6-overlay, and code-server |
| `platform` | `code` plus Python 3.14, Java 25, Kotlin, Gradle, Go, Rust, Node.js, and platform tools |
| `full` | `platform` plus JupyterLab, multi-language kernels, debugging, and security tools |

The `*-core` Bake targets are internal build layers, not supported runtime
images.

`full` includes JupyterLab kernels for Python, Bash, Rust via Evcxr, Go via
GoNB, and Kotlin.

`/workspace` is the bind-mounted project root. `/home/dev` preserves user
state such as history and configuration. Image-owned runtimes and tools live
outside `/home/dev`, so switching images or reusing the home volume does not
hide them.

## Optional auth

Compose binds to `127.0.0.1` by default, so code-server and JupyterLab can run
without app-level auth for trusted single-user local use. To enable protection,
set variables in `.env` or `runtime-config/config.env`:

```bash
PASSWORD='change-me'
JUPYTER_TOKEN='change-me-too'
```

Use `HASHED_PASSWORD` instead of `PASSWORD` when you already have a code-server
password hash. Caddy only routes traffic; code-server and JupyterLab own login
behavior.

`runtime-config/` is mounted read-only at `/etc/workspace` and excluded from
Git and the Docker build context.

To listen beyond loopback, set `WORKSPACE_BIND_ADDRESS=0.0.0.0` only behind an
authenticated workspace proxy such as Coder, or after configuring app
credentials and an appropriate network/TLS boundary.

## Enterprise overlay

```bash
cd templates/enterprise
just start
```

The enterprise module adds non-secret CA, proxy, Git, registry, and internal
tool configuration to `platform` by default. Keep secrets in
`templates/enterprise/secrets/`, environment variables, CI secrets, or a
platform secret store.

## Operational rules

- Prefer `just` and `docker buildx bake`.
- Keep managed service and shell config in the final runtime overlay.
- Keep credentials in the read-only `runtime-config/` mount.
- Treat `/home/dev` as persistent user state, not an image-owned tool location.
- Keep build logs gated and show only a short tail on failure.
- Add tests only when they freeze useful behavior or catch real regressions.
- Clean test containers and volumes; retain useful images and build cache.

## Requirements

- Docker with BuildKit/buildx
- Docker Compose v2 with `up --wait` support
- [`just`](https://just.systems) 1.54 or newer

## More docs

- [Images](docs/images.md)
- [Local development](docs/local-development.md)
- [Tool manifest](docs/tools.md)
- [Architecture](docs/architecture.md)
- [Coder integration](docs/coder.md)
- [Releasing](docs/releasing.md)
