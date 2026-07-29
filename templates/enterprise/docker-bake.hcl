variable "REGISTRY" {
  default = "registry.internal.example.com/workspace"
}

variable "TAG" {
  default = "latest"
}

variable "BASE_IMAGE" {
  default = "ghcr.io/jo-cube/workspace:platform"
}

variable "HTTP_PROXY" {
  default = ""
}

variable "HTTPS_PROXY" {
  default = ""
}

variable "NO_PROXY" {
  default = ""
}

group "default" {
  targets = ["enterprise"]
}

target "enterprise" {
  dockerfile = "Dockerfile"
  context    = "."
  tags       = ["${REGISTRY}:${TAG}"]
  args = {
    BASE_IMAGE      = BASE_IMAGE
    HTTP_PROXY      = HTTP_PROXY
    HTTPS_PROXY     = HTTPS_PROXY
    NO_PROXY        = NO_PROXY
    http_proxy      = HTTP_PROXY
    https_proxy     = HTTPS_PROXY
    no_proxy        = NO_PROXY
  }
  output = ["type=docker"]
}
