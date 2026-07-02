# Architecture

## Overlay model

The enterprise overlay does not build from scratch. It layers enterprise-specific configuration on top of a generic workspace image:

```
ghcr.io/jcube/workspace:polyglot   (generic base)
└── enterprise overlay
    ├── CA certificates
    ├── proxy configuration
    ├── Git enterprise defaults
    ├── Homebrew (optional)
    └── registry configuration
```

## Build-time vs runtime configuration

| Concern | When applied | How |
|---------|-------------|-----|
| CA certificates | Build time | `config/ca-certificates/` + `update-ca-certificates` |
| Git defaults | Build time | COPY to /etc/gitconfig |
| Homebrew + packages | Build time (optional) | ARG ENABLE_HOMEBREW |
| Proxy settings | Build and runtime | build args, compose env file, /etc/profile.d |
| Registry config | Runtime | `/etc/enterprise/registry/` examples and env vars |
| Registry credentials | Runtime | environment, Docker credentials, or /secrets/ |
| Secrets | Runtime | /secrets/ read-only mount |

## Security

- No secrets baked into images
- CA certificates and Git config are the only build-time additions
- Proxy URLs use placeholders in version control
- Secrets are mounted read-only at `/secrets/`
- Registry credentials should come from environment or secret mounts

## Extending

To add new enterprise tools:

1. **Static binary**: Download in the Dockerfile
2. **Homebrew**: Add to `config/Brewfile` and build with `ENABLE_HOMEBREW=true`
3. **Complex install**: Add the smallest Dockerfile step that installs it

## CI/CD pattern

```yaml
# Example CI build
steps:
  - name: Build enterprise overlay
    run: |
      install -m 0644 "$CI_TRUST_BUNDLE" config/ca-certificates/root-ca.crt
      REGISTRY=registry.internal.example.com/workspace \
        BASE_IMAGE=ghcr.io/jcube/workspace:platform \
        ENABLE_HOMEBREW=true \
        docker buildx bake enterprise --push
```

Compose is only the local runtime launcher. Use `just start` to build only when the local image is missing, or `just up` to rebuild explicitly.
