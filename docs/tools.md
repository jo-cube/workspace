# Tools

The Dockerfiles are the source of truth.

## Core (`code`, `platform`, `full`)

```text
bash, zsh, tmux, neovim, git, curl, wget, jq, ripgrep, fd, fzf,
bat, eza, tree, less, direnv, zoxide, starship, shellcheck, shfmt
```

## Languages (`platform`, `full`)

```text
uv, Python 3.15, IPython, ruff, mypy,
Java 25, Kotlin, Gradle,
Go 1.27, Rust stable, Node.js 26,
gcc, libc6-dev
```

Image-owned Python is stored under `/opt/uv-python`; `/home/dev` remains
persistent user state.

Java uses Temurin 25.0.5 through SDKMAN. Kotlin 2.4.21 runs on JDK 27 but
cannot emit JVM 27 bytecode; mixed Java/Kotlin Gradle builds targeting 27 fail
JVM-target validation. Java 26 is end-of-life, so Java 25 is the maintained
default with matching targets and no compatibility overrides. Project Gradle
wrappers may need a different JDK; select it with SDKMAN when required.

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

Run `./scripts/doctor.sh` inside a container for runtime checks. The smoke suite
builds a mixed Java/Kotlin Gradle application and executes every notebook kernel.
