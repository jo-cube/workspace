# Image flavors

## Choosing a flavor

| Use case | Flavor |
|----------|--------|
| Minimal container, no IDE | `base` |
| General development with browser IDE | `code` |
| Python-focused development | `python` |
| Java/Kotlin/Spring development | `jvm` |
| Multi-language projects | `polyglot` |
| Data science / notebooks | `lab` |
| Infrastructure / DevOps / platform work | `platform` |
| Everything available | `full` |

## Flavor details

### base (`docker/base.Dockerfile`)

Ubuntu 26.04 LTS foundation. Includes:
- Non-root `dev` user with sudo
- Core CLI tools (git, curl, jq, ripgrep, fzf, eza, bat, etc.)
- Neovim, tmux, starship prompt
- Caddy reverse proxy with workspace index page
- s6-overlay service supervisor
- Health endpoints via Caddy

### code (`docker/code.Dockerfile`)

Everything in `base` plus:
- code-server (VS Code in browser)
- Accessible at `http://localhost:8080/code/`

### python (`docker/python.Dockerfile`)

Everything in `code` plus:
- uv (fast Python package manager)
- Python 3.14
- ruff (linter/formatter)
- mypy (type checker)

### jvm (`docker/jvm.Dockerfile`)

Everything in `code` plus:
- Java 25 (Temurin)
- Kotlin (latest)
- Gradle (latest)
- Managed via SDKMAN

### polyglot (`docker/polyglot.Dockerfile`)

Everything in `code` plus all runtimes:
- Python 3.14 via uv
- Java 25 + Kotlin + Gradle
- Go 1.26
- Rust (stable)
- C linker for Cargo and cgo builds
- Node.js 24 (LTS) via fnm

### lab (`docker/lab.Dockerfile`)

Everything in `polyglot` plus:
- JupyterLab, enabled by the flavor
- Jupyter kernels for Python, Bash, Rust via Evcxr, Go via GoNB, and Kotlin

JupyterLab opens at `/workspace`. GoNB cells are compiled Go; use a normal
`func main` or GoNB's `%%` shortcut for statement cells.

### platform (`docker/platform.Dockerfile`)

Everything in `polyglot` plus:
- kubectl, helm, k9s, stern, kubectx/kubens
- httpie, xh, grpcurl, gron
- PostgreSQL client, Redis client, DuckDB, Kafka `kcat`, websocat, Miller, rsync
- s5cmd and MinIO mc for S3-compatible object storage
- RocksDB admin tools (`ldb`, `sst_dump`)
- datamash, pv, GNU parallel, and GNU awk for UNIX stream processing
- gh CLI, lazygit, delta
- just, yq

### full (`docker/full.Dockerfile`)

Everything: platform + lab + debug + security tools:
- JupyterLab with Python, Bash, Rust via Evcxr, Go via GoNB, and Kotlin kernels
- gdb, strace, ltrace, valgrind, tcpdump
- trivy, gitleaks
- hyperfine
- sqlite3

## Building specific flavors

```bash
# Single flavor (builds dependencies automatically)
just build platform

# Via bake directly
docker buildx bake polyglot

# Multiple flavors
docker buildx bake python jvm platform

# All flavors
just build-all
```

## Running specific flavors

```bash
# Start a specific flavor
just start polyglot

# Or via compose after building the image
FLAVOR=platform docker compose up -d --no-build
```

## Extending

To add a new flavor:

1. Create `docker/newflavor.Dockerfile` with `ARG BASE_IMAGE=...` and `FROM ${BASE_IMAGE}`
2. Add a `newflavor-core` target and a public `newflavor` runtime overlay target in `docker-bake.hcl`
3. Document the flavor in the README and image guide
