# Local development

## Prerequisites

- Docker with BuildKit/buildx and Compose v2 with `up --wait` support
- [just](https://just.systems) 1.54 or newer

## Start a workspace

```bash
just start           # code, build only if the selected image is missing
just start platform
just start full
```

Use `just up <flavor>` to rebuild before starting, or `just pull <flavor>` to
download a published image before `just start <flavor>`. Both start commands
wait up to 120 seconds for Caddy and every enabled browser service to be
healthy. A failed build or readiness check returns a failure; inspect
`just logs`, `just status`, or `just doctor` for details.

## Access and commands

| Method | Command / URL |
|--------|---------------|
| Dashboard | `http://localhost:8080` |
| Browser IDE | `http://localhost:8080/code/` |
| Jupyter | `http://localhost:8080/lab` (`full`) |
| Proxy liveness | `http://localhost:8080/health` |
| Container state and Docker health | `just status` |
| Interactive shell | `just shell` |
| Run a command | `just exec git status` |

Shells and commands run as `dev` in `/workspace` with `HOME=/home/dev`.
`just exec` preserves arguments and exit status, passes stdin through, and
works without a terminal:

```bash
just exec python -c 'print("hello from Python")'
printf 'hello\n' | just exec cat
just exec sh -c 'git status && git diff --stat'
```

Use an explicit shell such as `sh -c` when you need shell operators inside
the container. Use `just shell` for interactive programs that need a terminal.

## Image and environment selection

The launchers load `.env` beside their `justfile`. Exported shell variables take precedence, and an
explicit flavor argument overrides `FLAVOR`:

```dotenv
FLAVOR=full
TAG=latest
REGISTRY=ghcr.io/jo-cube
WORKSPACE_PORT=9090
WORKSPACE_BIND_ADDRESS=127.0.0.1
PASSWORD='change-me'
JUPYTER_TOKEN='change-me-too'
```

This selects `ghcr.io/jo-cube/workspace:full-latest`. To use a specific published
release, set its `TAG`, then run `just pull` followed by `just start`.
Builds, pulls, and startup share the same image selection. See [Images](images.md).

## Authentication

Set `PASSWORD` or `HASHED_PASSWORD` for code-server, and `JUPYTER_TOKEN` for
JupyterLab. Unset credentials allow trusted single-user local operation.
Compose binds to loopback by default. Listen on `0.0.0.0` only behind an
authenticated workspace proxy such as Coder, or with app credentials and an
appropriate network/TLS boundary.

Credentials can also live in `runtime-config/config.env`:

```bash
PASSWORD='change-me'
JUPYTER_TOKEN='change-me-too'
```

This optional shell-format file is gitignored, excluded from the build
context, and mounted read-only at `/etc/workspace/config.env`. Quote values
so shell metacharacters stay literal. A deployment can mount it elsewhere
and set `WORKSPACE_CONFIG_FILE` to that container path.

## Persistent data

| Path | Storage | Purpose |
|------|---------|---------|
| `/workspace` | `./workspace` bind mount | Project files |
| `/home/dev` | `home` named volume | User configuration and history |
| `/cache` | `cache` named volume | Package caches |
| `/etc/workspace` | `./runtime-config` read-only bind mount | Optional app configuration |

Image dotfiles seed a new home volume once; image updates preserve user edits.
Image-owned runtimes live outside `/home/dev`, so they remain available when
switching flavors or reusing volumes.

`just start` makes the workspace bind root writable for the fixed `dev` user.
This assumes a trusted single-user host; use a deployment-specific UID or
mount policy on a multi-user host.

```bash
just down              # stop, preserve all data
just reset             # remove home/cache volumes, preserve project files
just reset-workspace   # also delete ./workspace contents
just clean-build-cache # prune Docker build cache
just clean             # reset volumes and prune build cache
```

## Health and validation

```bash
just health    # probe Caddy and every enabled browser service
just doctor    # also check tools and filesystem permissions
just logs      # follow service logs
```

`just health` runs inside the selected Compose container, so it works with
custom host ports and bind addresses. `/health` is only a Caddy liveness probe.

For repository changes, run:

```bash
python3 -m unittest discover -s tests -v  # recipe behavior and Compose/Bake agreement
./scripts/smoke-test.sh all              # build and exercise every image and kernel
```

The recipe tests require Python 3, Just, and the Docker CLI; they do not need
a running Docker daemon. Smoke tests use isolated containers and volumes.

## Jupyter kernels

`full` includes Python, Bash, Rust via Evcxr, Go via GoNB, and Kotlin kernels.
JupyterLab opens at `/workspace`. GoNB uses the Go compiler, so wrap expressions
in a function or use its `%%` shortcut:

```go
%%
fmt.Println(2 + 2)
```
