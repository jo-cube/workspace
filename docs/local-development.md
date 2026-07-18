# Local development

## Prerequisites

- Docker with BuildKit enabled
- Docker Compose v2
- [just](https://just.systems) command runner

## Start workspace

```bash
# Default (code flavor, build only if missing)
just start

# Specific flavor
just start polyglot
just start platform
just start full
```

## Access

| Method | Command / URL |
|--------|---------------|
| Dashboard | `http://localhost:8080` |
| Browser IDE | `http://localhost:8080/code/` |
| Jupyter | `http://localhost:8080/lab` (when enabled) |
| Health | `http://localhost:8080/health` |
| Status | `http://localhost:8080/status` |
| Shell | `just shell` |

The dashboard at root shows services with live status, system info, and links.
JupyterLab opens at `/workspace`, the bind-mounted project root. User state and shell history live in `/home/dev`.

## Jupyter kernels

`lab` and `full` include Python, Bash, Rust via Evcxr, Go via GoNB, and Kotlin kernels.

GoNB uses the Go compiler, so bare expressions like `2 + 2` are not valid top-level cells. Use a normal `func main`:

```go
func main() {
    fmt.Println(2 + 2)
}
```

Or use GoNB's `%%` shortcut, which wraps the cell body in `func main`:

```go
%%
fmt.Println(2 + 2)
```

## Volumes

```yaml
volumes:
  - ./workspace:/workspace       # your projects
  - home:/home/dev               # persists dotfiles, shell history
  - cache:/cache                 # package caches (uv, gradle, go, etc.)
  - ./runtime-config:/etc/workspace:ro  # optional local app config
```

The `home` and `cache` volumes persist across container recreations. Image
dotfiles seed a new home volume once; image updates do not overwrite later user
changes. Remove the volumes with:

```bash
just reset
```

`./workspace` is a host bind mount, not a Docker volume, so `just reset` keeps its files. To remove those files too without pruning Docker build cache:

```bash
just reset-workspace
```

`just start` and `just up` make the bind root writable for the image's fixed
`dev` user. This assumes the documented trusted single-user host; use a
deployment-specific UID or mount policy on a multi-user host.

## Environment overrides

Create a `.env` file for host-side selection:

```bash
FLAVOR=full
WORKSPACE_PORT=9090
WORKSPACE_BIND_ADDRESS=127.0.0.1
PASSWORD='change-me'
JUPYTER_TOKEN='change-me-too'
```

Service defaults come from the image flavor. Use `lab` or `full` for JupyterLab.
Set `PASSWORD` or `HASHED_PASSWORD` for code-server auth. Set `JUPYTER_TOKEN` for JupyterLab auth. Caddy is the path router.
Leave those values unset for an unauthenticated local container on a trusted loopback-only setup.
Compose binds to loopback by default. Set `WORKSPACE_BIND_ADDRESS=0.0.0.0` only
behind an authenticated workspace proxy such as Coder, or after configuring
app credentials and a suitable network/TLS boundary.

You can also use a generic runtime config file:

```bash
mkdir -p runtime-config
cat > runtime-config/config.env
```

```bash
PASSWORD='change-me'
JUPYTER_TOKEN='change-me-too'
```

`runtime-config/config.env` is gitignored and mounted read-only at
`/etc/workspace/config.env`. It is also excluded from the Docker build context,
so credentials stay out of image layers. A runtime connector can mount the same
file elsewhere and set `WORKSPACE_CONFIG_FILE` to that container path.
Use quoted values for secrets or hashes so shell metacharacters stay literal.

## Health check

```bash
# Quick check from host
just health

# Full check inside container
just doctor
```

## Rebuilding

```bash
# Start without rebuilding when the image exists
just start

# Rebuild and start
just up full

# Rebuild one flavor and its final runtime overlay
docker buildx bake full

# Full clean rebuild
just clean
just up full
```

`just clean` also prunes Docker build cache. Use `just reset` when you only want fresh runtime volumes, or `just reset-workspace` when you also want to empty the bind-mounted project directory.

## Useful commands

```bash
just status     # show container state
just logs       # follow logs
just doctor     # health checks inside container
just start           # start, build only if image is missing
just reset            # remove home/cache volumes, keep ./workspace and build cache
just reset-workspace  # remove home/cache volumes and ./workspace contents
just            # show all available commands
```

## Tips

- The `workspace/` directory is bind-mounted, so its files survive `just reset`.
- Shell history and user-edited config persist in the `home` volume. Use
  `just reset` when you intentionally want the current image defaults again.
- Package caches (uv, gradle, go modules) persist in the `cache` volume.
- Use `just shell` for quick terminal access.
- The workspace index page at root shows which services are available.
- `docker buildx bake` resolves all parent images automatically. Use bake/`just`, not `docker compose up --build`.
