# Images

## Supported images

| Use case | Image |
|----------|-------|
| Browser IDE and core tools | `code` |
| Multi-language and platform development | `platform` |
| Notebooks, debugging, and security work | `full` |

### code

Includes:

- Ubuntu 26.04 LTS
- Non-root `dev` user with sudo
- Core shell, editor, Git, network, and productivity tools
- Caddy reverse proxy and s6-overlay
- code-server at `/code/`

### platform

Everything in `code` plus:

- Python 3.14 via uv
- Java 25, Kotlin, and Gradle via SDKMAN
- Go 1.26
- Rust stable
- Node.js 24
- Kubernetes tools: kubectl, Helm, k9s, stern, kubectx, kubens
- HTTP/gRPC/WebSocket clients: curl, xh, grpcurl, websocat
- PostgreSQL, Redis, DuckDB, Kafka, S3, and RocksDB clients
- Git and stream-processing helpers

### full

Everything in `platform` plus:

- JupyterLab at `/lab`
- Python, Bash, Rust, Go, and Kotlin kernels
- gdb, strace, ltrace, valgrind, tcpdump
- Trivy and Gitleaks
- hyperfine and sqlite3

## Internal build layers

The Bake graph uses `base-core`, `code-core`, `polyglot-core`,
`platform-core`, and `full-core` to preserve expensive build cache. These are
implementation details and are not published or supported as runtime images.

## Build and run

```bash
just build code
just build platform
just build full
just build-all

just start code
just start platform
just start full
```

Add another supported image only when it serves a distinct user group and can
be included in CI, smoke tests, releases, and documentation.
