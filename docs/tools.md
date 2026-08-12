# Tools

The Dockerfiles are the source of truth.

## Core (`code`, `platform`, `full`)

```text
bash, zsh, tmux, neovim, git, curl, wget, jq, ripgrep, fd, fzf,
bat, eza, tree, less, direnv, zoxide, starship, shellcheck, shfmt
```

## Languages (`platform`, `full`)

```text
uv, Python 3.14, IPython, ruff, mypy,
Java 25, Kotlin, Gradle,
Go 1.26, Rust stable, Node.js 24,
gcc, libc6-dev
```

Image-owned Python is stored under `/opt/uv-python`; `/home/dev` remains
persistent user state.

## Platform tools (`platform`, `full`)

```text
kubectl, helm, k9s, stern, kubectx, kubens,
xh, grpcurl, gron, websocat,
postgresql-client, redis-tools, duckdb, kcat, miller, rsync,
s5cmd, mc, ldb, sst_dump,
datamash, pv, parallel, gawk,
gh, lazygit, delta, just, yq
```

RocksDB tools are for administration and debugging. Prefer copied or
checkpointed databases; use `--try_load_options` and lower-impact secondary
access where appropriate.

## Full-only tools

```text
jupyter-lab,
bash_kernel, evcxr_jupyter, gonb, goimports, gopls,
kotlin-jupyter-kernel,
gdb, strace, ltrace, valgrind, tcpdump, sqlite3,
trivy, gitleaks, hyperfine
```

Run `./scripts/doctor.sh` inside a container for runtime checks. The full smoke
test executes every registered notebook kernel.
