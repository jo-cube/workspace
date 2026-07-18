# Configuration guide

## CA certificates

Place `.crt` files in `config/ca-certificates/`. They are added to the system trust store at build time.

```bash
config/ca-certificates/
├── root-ca.crt
└── issuing-ca.crt
```

Real certificate files are gitignored. If CI stores them as secrets, write them into this directory before `just build`. Debian's `update-ca-certificates` expects certificate files in this directory to end in `.crt`; the basename is yours.

```bash
install -m 0644 "$CI_TRUST_BUNDLE" config/ca-certificates/root-ca.crt
just build
```

## Proxy

Edit `config/proxy.env` with env-file syntax:

```bash
HTTP_PROXY=http://proxy.internal.example.com:8080
HTTPS_PROXY=http://proxy.internal.example.com:8080
NO_PROXY=localhost,127.0.0.1,.internal.example.com
http_proxy=http://proxy.internal.example.com:8080
https_proxy=http://proxy.internal.example.com:8080
no_proxy=localhost,127.0.0.1,.internal.example.com
```

`just build` passes proxy variables to Docker buildx bake. `docker compose` also loads this file at runtime. Do not put proxy credentials in this file.

## Workspace authentication

Put optional code-server and Jupyter credentials in
`runtime-config/config.env`:

```bash
PASSWORD='change-me'
JUPYTER_TOKEN='change-me-too'
```

The directory is gitignored, excluded from the Docker build context, and
mounted read-only at `/etc/workspace/`. Compose publishes to host loopback by
default; keep that boundary for passwordless use.

## Git

Edit `config/git/gitconfig` for enterprise defaults:

```ini
[http]
    sslCAInfo = /etc/ssl/certs/ca-certificates.crt
    proxy = http://proxy.internal.example.com:8080

[url "https://github.internal.example.com/"]
    insteadOf = gh:
```

## Homebrew

Enable at build time:

```bash
ENABLE_HOMEBREW=true just build
```

Add enterprise packages to `config/Brewfile`:

```ruby
tap "internal/tools", "https://github.internal.example.com/platform/homebrew-tools"
brew "internal-cli"
brew "platform-ctl"
```

## Package registries

Place non-secret configuration in `config/registry/`:

```
config/registry/
├── .npmrc.example
├── pip.conf.example
├── maven-settings.xml.example
├── gradle-init.gradle.example
├── cargo-config.toml.example
└── go.env.example
```

Copy examples to real filenames when you want them active:

```bash
cp config/registry/pip.conf.example config/registry/pip.conf
cp config/registry/.npmrc.example config/registry/.npmrc
```

Point tools at active files through compose, CI, or your shell:

```bash
PIP_CONFIG_FILE=/etc/enterprise/registry/pip.conf
NPM_CONFIG_USERCONFIG=/etc/enterprise/registry/.npmrc
GOENV=/etc/enterprise/registry/go.env
mvn -s /etc/enterprise/registry/maven-settings.xml ...
```

Docker registry mirrors and auth usually belong on the host Docker daemon or CI runner, not inside this image. Keep auth tokens in Docker credentials, CI secrets, or `/secrets/`.

## Secrets

Create a `secrets/` directory (gitignored) for runtime secrets:

```
secrets/
├── vault-token
├── ssh-key
└── registry-auth.json
```

Mounted read-only at `/secrets/` in the container.

## Environment variables

| Variable | Purpose |
|----------|---------|
| `HTTP_PROXY` / `HTTPS_PROXY` | Corporate proxy |
| `NO_PROXY` | Proxy bypass list |
| `NPM_TOKEN` | npm registry auth |
| `PIP_INDEX_URL` | Python package index |
| `VAULT_ADDR` | HashiCorp Vault address |
| `VAULT_TOKEN` | Vault auth (prefer /secrets/ mount) |
