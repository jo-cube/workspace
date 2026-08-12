# justfile

registry := env("REGISTRY", "ghcr.io/jo-cube")
tag := env("TAG", "latest")
flavor := env("FLAVOR", "code")

# List available commands
default:
    @just --list

# Build a specific flavor (and its dependencies)
build target=flavor:
    docker buildx bake {{ target }}

# Build all supported images
build-all:
    docker buildx bake all

# Rebuild and start a specific flavor
up target=flavor:
    just build {{ target }}
    mkdir -p workspace runtime-config
    chmod 0777 workspace
    REGISTRY={{ registry }} FLAVOR={{ target }} docker compose up -d --no-build

# Start a flavor, building only when the local runtime image is missing
start target=flavor:
    @image="{{ registry }}/workspace:{{ target }}"; \
    docker image inspect "$image" >/dev/null 2>&1 || just build {{ target }}; \
    mkdir -p workspace runtime-config; \
    chmod 0777 workspace; \
    REGISTRY={{ registry }} FLAVOR={{ target }} docker compose up -d --no-build

# Stop the running workspace
down:
    docker compose down

# Open a dev shell in the running workspace
shell:
    docker compose exec --user dev --env HOME=/home/dev --env USER=dev workspace zsh

# Follow workspace logs
logs:
    docker compose logs -f

# Show running container status
status:
    docker compose ps

# Run health checks inside the container
doctor:
    docker compose exec workspace bash /scripts/doctor.sh

# Push a specific flavor to registry
push target=flavor:
    REGISTRY={{ registry }} TAG={{ tag }} docker buildx bake {{ target }} --push

# Push all images to registry
push-all:
    REGISTRY={{ registry }} TAG={{ tag }} docker buildx bake all --push

# Reset runtime data, keep build cache
reset:
    docker compose down -v

# Reset runtime data and bind-mounted workspace files, keep build cache
reset-workspace: reset
    mkdir -p workspace
    find workspace -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +

# Remove Docker build cache
clean-build-cache:
    docker builder prune -f

# Remove runtime data and Docker build cache
clean: reset clean-build-cache

# Quick Caddy liveness check from host
health:
    @curl --noproxy '*' -sf http://localhost:${WORKSPACE_PORT:-8080}/health >/dev/null && echo "workspace healthy"
