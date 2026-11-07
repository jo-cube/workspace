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

## Utility compatibility

kubectl 1.37 follows Kubernetes' [one-minor version-skew policy](https://kubernetes.io/releases/version-skew-policy/):
it supports API servers 1.36–1.38. Helm 4.3 uses Kubernetes 1.37 clients and
[supports 1.34–1.37](https://helm.sh/docs/topics/version_skew/).
Choose client versions appropriate to your cluster; the bundled pair's supported
ranges overlap at 1.36–1.37.

DuckDB 2 reads and writes existing 1.x databases while retaining their storage
version. New databases default to the 2.0 format and cannot be opened by 1.x.
Keep backups before upgrading shared databases; use DuckDB's explicit storage
version or export/import procedures when exchanging files with older clients.
Workspace does not migrate files automatically. Review the
[2.0 migration guide](https://duckdb.org/docs/2.0/operations_manual/migration)
for SQL and extension changes as well.

The existing `mc` command now uses [Silo's maintained mcli fork](https://github.com/pgsty/mc).
Installing it as `mc` preserves `~/.mc` and `MC_*` configuration.
It retains MinIO/Silo administrative commands that `s5cmd` does not provide;
`s5cmd` remains useful for bulk object transfers. The fork disables MinIO-operated
update, SUBNET, licensing, and telemetry services. Server-specific behavior is
best effort: check the [compatibility notes](https://silo.pgsty.com/compatibility/mcli/)
and test against your server version. No user configuration is migrated.

grpcurl retains a temporary `x/net` override for HTTP/2 fixes absent from
its current release.

Hyperfine 2 executes commands directly by default. Shell operators and expansion
require an explicit shell choice, such as `-S` or `--shell bash`.
JSON exports use schema version 2; CSV and table-export layouts also changed.
Update consumers of those formats using the
[upstream migration notes](https://github.com/sharkdp/hyperfine/releases/tag/v2.0.0).

Stern 1.35 custom templates using `--timestamps` must print `.Timestamp`
explicitly; `.Message` now contains only the message. Built-in output is unchanged.

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
