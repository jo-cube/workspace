# enterprise

Enterprise overlay for the generic workspace images. Use this as a small template for corporate trust, proxy, registry, Git, and internal-tool defaults.

## Quick start

```bash
# Start, building only if the local enterprise image is missing
just start

# Shell access
just shell

# Rebuild and start
just up

# Build with a different base
BASE_IMAGE=ghcr.io/jo-cube/workspace:full just build
```

## What this adds

| Feature | Path / mechanism |
|---------|-----------------|
| CA certificates | `config/ca-certificates/*.crt` → system trust store |
| Proxy config | `config/proxy.env` → build args, compose env, login shells |
| Git defaults | `config/git/gitconfig` → `/etc/gitconfig` |
| Homebrew | Optional via `ENABLE_HOMEBREW=true` build arg |
| Enterprise tools | `config/Brewfile` or small Dockerfile additions |
| Registry config | `config/registry/` → `/etc/enterprise/registry/` |
| Secrets | `./secrets/` → `/secrets/:ro` (not committed) |

## Commands

```bash
just                    # show all commands
just build              # build enterprise image
just build-with-homebrew # build with Homebrew enabled
just start              # start, build only if image is missing
just up                 # rebuild + start
just down               # stop
just shell              # open zsh
just logs               # follow logs
just push               # push to enterprise registry
just clean              # remove volumes
```

## Configuration

1. Place public CA certificates in `config/ca-certificates/`. CI can materialize secret-managed files there before build.
2. Edit `config/proxy.env` with non-secret proxy URLs.
3. Edit `config/git/gitconfig` for internal GitHub or enterprise Git hosting.
4. Copy registry examples in `config/registry/` to real filenames and edit endpoints.
5. Add internal tools to `config/Brewfile` or a small Dockerfile install step.
6. Put runtime secrets in `secrets/` or your platform secret store, never in images.

## Documentation

- [Architecture](docs/architecture.md)
- [Configuration guide](docs/configuration.md)

## Agent notes

- Keep this as a template. Do not invent company-specific endpoints, names, tools, or policies.
- Keep secrets out of images and examples.
- Build with `docker buildx bake` or `just`; do not use `docker compose up --build`.
- Prefer the root generic workspace image module for reusable tools. Put enterprise-only additions here.
