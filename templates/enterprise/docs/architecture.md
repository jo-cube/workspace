# Architecture

## Overlay model

The enterprise overlay does not build from scratch. It layers enterprise-specific configuration on top of a generic workspace image:

```
ghcr.io/jo-cube/workspace:platform   (generic base)
└── enterprise overlay
    ├── CA certificates
    ├── proxy configuration
    ├── Git enterprise defaults
    └── registry configuration
```

## Build-time vs runtime configuration

| Concern | When applied | How |
|---------|-------------|-----|
| CA certificates | Build time | `config/ca-certificates/` + `update-ca-certificates` |
| Git defaults | Build time | COPY to /etc/gitconfig |
| Proxy settings | Build and runtime | build args, compose env file, /etc/profile.d |
| Registry config | Runtime | `/etc/enterprise/registry/` examples and env vars |
| Registry credentials | Runtime | environment, Docker credentials, or /secrets/ |
| App authentication | Runtime | `/etc/workspace/config.env` read-only mount |
| Secrets | Runtime | /secrets/ read-only mount |

## Security

- No secrets baked into images
- CA certificates and Git config are the only build-time additions
- Proxy URLs use placeholders in version control
- Secrets are mounted read-only at `/secrets/`
- App credentials are mounted read-only at `/etc/workspace/`, not baked
- Registry credentials should come from environment or secret mounts
- Compose publishes to host loopback unless the operator opts into another bind address

The inherited `/home/dev` volume is user state. Image dotfiles seed it once;
managed enterprise defaults belong under `/etc` so image updates can apply them.

## Extending

Add enterprise tools with the smallest practical Dockerfile install step.

## CI/CD pattern

```yaml
# Example CI build
steps:
  - name: Build enterprise overlay
    run: |
      install -m 0644 "$CI_TRUST_BUNDLE" config/ca-certificates/root-ca.crt
      REGISTRY=registry.internal.example.com/workspace \
        BASE_IMAGE=ghcr.io/jo-cube/workspace:platform \
        docker buildx bake enterprise --push
```

Compose is only the local runtime launcher. Use `just start` to build only when the local image is missing, or `just up` to rebuild explicitly.
