# Load only this project's optional configuration.
set dotenv-command := "if [ -f .env ]; then cat .env; fi"
set positional-arguments
set shell := ["sh", "-eu", "-c"]

export REGISTRY := if env("REGISTRY", "") == "" { "ghcr.io/jo-cube" } else { env("REGISTRY") }
export TAG := if env("TAG", "") == "" { "latest" } else { env("TAG") }
flavor := if env("FLAVOR", "") == "" { "code" } else { env("FLAVOR") }

# List available commands
default:
    @just --list

# Build a specific flavor (and its dependencies)
build target=flavor: (_validate-flavor target)
    docker buildx bake "$1"

# Build all supported images
build-all:
    docker buildx bake all

# Rebuild and wait for a healthy workspace
up target=flavor: (build target)
    just start "$1"

# Start a flavor, building only when the selected image is missing
start target=flavor: (_validate-flavor target)
    @image="${REGISTRY}/workspace:${1}-${TAG}"; \
    if ! docker image inspect "$image" >/dev/null 2>&1; then just build "$1"; fi; \
    mkdir -p workspace runtime-config; \
    chmod 0777 workspace; \
    FLAVOR="$1" docker compose up --wait --wait-timeout 120 --no-build

# Pull a published flavor at TAG without building locally
pull target=flavor: (_validate-flavor target)
    FLAVOR="$1" docker compose pull workspace

# Stop the running workspace
down:
    docker compose down

# Open a dev shell in the running workspace
shell:
    docker compose exec --user dev --env HOME=/home/dev --env USER=dev --workdir /workspace workspace zsh -l

# Run a command as dev; preserve arguments, stdin, and exit status
exec +command:
    @docker compose exec -T --user dev --env HOME=/home/dev --env USER=dev --workdir /workspace workspace "$@"

# Follow workspace logs
logs:
    docker compose logs -f

# Show container state, including Docker health status
status:
    docker compose ps

# Run health checks inside the container
doctor:
    docker compose exec -T workspace bash /scripts/doctor.sh

# Check the proxy and every enabled browser service
health:
    @docker compose exec -T workspace /scripts/healthcheck.sh
    @echo "workspace healthy"

# Push a specific flavor to registry
push target=flavor: (_validate-flavor target)
    docker buildx bake "$1" --push

# Push all images to registry
push-all:
    docker buildx bake all --push

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

_validate-flavor target:
    @case "$1" in code|platform|full) ;; *) echo "Unsupported flavor: $1 (expected code, platform, or full)" >&2; exit 1 ;; esac
