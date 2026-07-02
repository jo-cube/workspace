# Tools

Tools are organized by image flavor. The Dockerfiles are the source of truth for what is installed.

## Groups

| Group | Included in | Description |
|-------|-------------|-------------|
| core | all flavors | Shell, editor, productivity |
| debug | full | System debugging, profiling |
| http-api | platform, full | HTTP/gRPC/WS clients |
| data-storage | platform, full | Database clients |
| object-storage | platform, full | S3-compatible object storage clients |
| rocksdb | platform, full | RocksDB admin/debug tools |
| stream-processing | platform, full | UNIX stream processing helpers |
| platform | platform, full | Kubernetes/cloud ops |
| security | full | Scanning, secrets |
| git-productivity | platform, full | Git workflow |
| build-runtime | all flavors | Make, just, yq |
| notebooks | lab, full | JupyterLab kernels |
| metrics | full | Code stats, benchmarking |
| homebrew | enterprise only | Optional package manager |

## Core tools (all flavors)

```
bash, zsh, tmux, neovim, git, curl, wget, jq, ripgrep, fd, fzf,
bat, eza, tree, less, direnv, zoxide, starship, shellcheck, shfmt
```

## Platform tools

```
kubectl, helm, k9s, stern, kubectx, kubens, httpie, xh, grpcurl, gron,
postgresql-client, redis-tools, duckdb, kcat, websocat, miller, rsync,
s5cmd, mc, ldb, sst_dump, datamash, pv, parallel, gawk,
gh, lazygit, delta, just, yq
```

These are meant for common platform debugging and data plumbing: cluster checks,
API calls, database/message-queue inspection, object storage copies, and quick
stream transforms. They are helpers, not a replacement for project-specific
tooling in `/workspace`.

RocksDB tools (`ldb`, `sst_dump`) are admin/debug tools. Prefer copied or
checkpointed databases; use `--try_load_options` when opening DBs, and
`--secondary_path` for lower-impact reads against a live DB.

## Full-only extras

```
gdb, strace, ltrace, valgrind, tcpdump, sqlite3, trivy, gitleaks, hyperfine
```

## Notebook kernels

```
python, bash_kernel, evcxr_jupyter, gonb, goimports, gopls, kotlin-jupyter-kernel
```

Available in `lab` and `full` through JupyterLab at `/lab`.

## Polyglot build support

```
gcc, libc6-dev
```

## Adding tools

1. Add the install step in the correct Dockerfile.
2. Document the tool in this guide and the image guide.
3. Run `./scripts/doctor.sh` inside a built container when you want a full runtime check.

## Homebrew (optional)

Homebrew is supported as an optional feature for the enterprise overlay. It is not installed in generic images by default because:
- It adds significant image size
- Most tools are available as static binaries
- Enterprise tools may require Homebrew taps

Enable in the enterprise overlay with `ENABLE_HOMEBREW=true`.
