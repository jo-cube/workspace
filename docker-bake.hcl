// Build the supported workspace images with: docker buildx bake <target>

variable "REGISTRY" {
  default = "ghcr.io/jo-cube"
}

variable "TAG" {
  default = "latest"
}

variable "CACHE_REGISTRY" {
  default = "ghcr.io/jo-cube"
}

variable "CACHE_IMAGE" {
  default = "workspace-cache"
}

variable "CI" {
  default = ""
}

group "default" {
  targets = ["code"]
}

group "all" {
  targets = ["code", "platform", "full"]
}

target "base-core" {
  dockerfile = "docker/base.Dockerfile"
  context    = "."
  cache-from = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:base-core"] : []
  cache-to   = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:base-core,mode=max"] : []
}

target "code-core" {
  dockerfile = "docker/code.Dockerfile"
  context    = "."
  args       = { BASE_IMAGE = "${REGISTRY}/workspace:base-core" }
  contexts   = { "${REGISTRY}/workspace:base-core" = "target:base-core" }
  cache-from = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:code-core"] : []
  cache-to   = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:code-core,mode=max"] : []
}

target "code" {
  dockerfile = "docker/runtime.Dockerfile"
  context    = "."
  tags       = ["${REGISTRY}/workspace:code-${TAG}", "${REGISTRY}/workspace:code"]
  args       = { BASE_IMAGE = "${REGISTRY}/workspace:code-core" }
  contexts   = { "${REGISTRY}/workspace:code-core" = "target:code-core" }
  output     = CI == "" ? ["type=docker"] : []
}

target "polyglot-core" {
  dockerfile = "docker/polyglot.Dockerfile"
  context    = "."
  args       = { BASE_IMAGE = "${REGISTRY}/workspace:code-core" }
  contexts   = { "${REGISTRY}/workspace:code-core" = "target:code-core" }
  cache-from = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:polyglot-core"] : []
  cache-to   = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:polyglot-core,mode=max"] : []
}

target "platform-core" {
  dockerfile = "docker/platform.Dockerfile"
  context    = "."
  args       = { BASE_IMAGE = "${REGISTRY}/workspace:polyglot-core" }
  contexts   = { "${REGISTRY}/workspace:polyglot-core" = "target:polyglot-core" }
  cache-from = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:platform-core"] : []
  cache-to   = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:platform-core,mode=max"] : []
}

target "platform" {
  dockerfile = "docker/runtime.Dockerfile"
  context    = "."
  tags       = ["${REGISTRY}/workspace:platform-${TAG}", "${REGISTRY}/workspace:platform"]
  args       = { BASE_IMAGE = "${REGISTRY}/workspace:platform-core" }
  contexts   = { "${REGISTRY}/workspace:platform-core" = "target:platform-core" }
  output     = CI == "" ? ["type=docker"] : []
}

target "full-core" {
  dockerfile = "docker/full.Dockerfile"
  context    = "."
  args       = { BASE_IMAGE = "${REGISTRY}/workspace:platform-core" }
  contexts   = { "${REGISTRY}/workspace:platform-core" = "target:platform-core" }
  cache-from = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:full-core"] : []
  cache-to   = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:full-core,mode=max"] : []
}

target "full" {
  dockerfile = "docker/runtime.Dockerfile"
  context    = "."
  tags       = ["${REGISTRY}/workspace:full-${TAG}", "${REGISTRY}/workspace:full", "${REGISTRY}/workspace:latest"]
  args       = { BASE_IMAGE = "${REGISTRY}/workspace:full-core" }
  contexts   = { "${REGISTRY}/workspace:full-core" = "target:full-core" }
  output     = CI == "" ? ["type=docker"] : []
}
