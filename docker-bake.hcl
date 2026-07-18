// docker-bake.hcl
// Build the workspace image family with: docker buildx bake <target>
//
// Runtime assets use a final overlay so s6/Caddy/dotfile edits rebuild quickly
// Python/JVM/Rust/Node/platform tool installs.

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
  targets = ["base", "code"]
}

group "all" {
  targets = ["base", "code", "python", "jvm", "polyglot", "lab", "platform", "full"]
}

target "base-core" {
  dockerfile = "docker/base.Dockerfile"
  context    = "."
  cache-from = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:base-core"] : []
  cache-to   = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:base-core,mode=max"] : []
}

target "base" {
  dockerfile = "docker/runtime.Dockerfile"
  context    = "."
  tags       = ["${REGISTRY}/workspace:base-${TAG}", "${REGISTRY}/workspace:base"]
  args       = { BASE_IMAGE = "${REGISTRY}/workspace:base-core" }
  contexts   = { "${REGISTRY}/workspace:base-core" = "target:base-core" }
  output     = CI == "" ? ["type=docker"] : []
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

target "python-core" {
  dockerfile = "docker/python.Dockerfile"
  context    = "."
  args       = { BASE_IMAGE = "${REGISTRY}/workspace:code-core" }
  contexts   = { "${REGISTRY}/workspace:code-core" = "target:code-core" }
  cache-from = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:python-core"] : []
  cache-to   = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:python-core,mode=max"] : []
}

target "python" {
  dockerfile = "docker/runtime.Dockerfile"
  context    = "."
  tags       = ["${REGISTRY}/workspace:python-${TAG}", "${REGISTRY}/workspace:python"]
  args       = { BASE_IMAGE = "${REGISTRY}/workspace:python-core" }
  contexts   = { "${REGISTRY}/workspace:python-core" = "target:python-core" }
  output     = CI == "" ? ["type=docker"] : []
}

target "jvm-core" {
  dockerfile = "docker/jvm.Dockerfile"
  context    = "."
  args       = { BASE_IMAGE = "${REGISTRY}/workspace:code-core" }
  contexts   = { "${REGISTRY}/workspace:code-core" = "target:code-core" }
  cache-from = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:jvm-core"] : []
  cache-to   = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:jvm-core,mode=max"] : []
}

target "jvm" {
  dockerfile = "docker/runtime.Dockerfile"
  context    = "."
  tags       = ["${REGISTRY}/workspace:jvm-${TAG}", "${REGISTRY}/workspace:jvm"]
  args       = { BASE_IMAGE = "${REGISTRY}/workspace:jvm-core" }
  contexts   = { "${REGISTRY}/workspace:jvm-core" = "target:jvm-core" }
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

target "polyglot" {
  dockerfile = "docker/runtime.Dockerfile"
  context    = "."
  tags       = ["${REGISTRY}/workspace:polyglot-${TAG}", "${REGISTRY}/workspace:polyglot"]
  args       = { BASE_IMAGE = "${REGISTRY}/workspace:polyglot-core" }
  contexts   = { "${REGISTRY}/workspace:polyglot-core" = "target:polyglot-core" }
  output     = CI == "" ? ["type=docker"] : []
}

target "lab-core" {
  dockerfile = "docker/lab.Dockerfile"
  context    = "."
  args       = { BASE_IMAGE = "${REGISTRY}/workspace:polyglot-core" }
  contexts   = { "${REGISTRY}/workspace:polyglot-core" = "target:polyglot-core" }
  cache-from = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:lab-core"] : []
  cache-to   = CI != "" ? ["type=registry,ref=${CACHE_REGISTRY}/${CACHE_IMAGE}:lab-core,mode=max"] : []
}

target "lab" {
  dockerfile = "docker/runtime.Dockerfile"
  context    = "."
  tags       = ["${REGISTRY}/workspace:lab-${TAG}", "${REGISTRY}/workspace:lab"]
  args       = { BASE_IMAGE = "${REGISTRY}/workspace:lab-core" }
  contexts   = { "${REGISTRY}/workspace:lab-core" = "target:lab-core" }
  output     = CI == "" ? ["type=docker"] : []
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
