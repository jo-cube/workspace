# Coder integration

This image family works with self-hosted [Coder](https://coder.com) instances as workspace images.

## How it works

Coder provisions containers from workspace templates. These images provide:
- code-server as the browser IDE (Coder's built-in web terminal also works)
- A single proxy port (8080) for all web services
- SSH access via `coder ssh`

The Coder agent runs as `dev`; s6 remains PID 1 and continues to supervise Caddy,
code-server, JupyterLab, and workspace-status. The example below does not publish a
host port or require privileged mode.

## Coder template example

Minimal Terraform template for a Docker-based Coder workspace:

```hcl
terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  os   = "linux"
  arch = data.coder_provisioner.me.arch
  dir  = "/workspace"
}

resource "docker_image" "workspace" {
  name         = "ghcr.io/jo-cube/workspace:platform"
  keep_locally = true
}

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"
}

resource "docker_volume" "workspace" {
  name = "coder-${data.coder_workspace.me.id}-workspace"
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count

  name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  image = docker_image.workspace.image_id
  hostname = data.coder_workspace.me.name

  # s6-overlay treats Docker CMD as the main service, so /init still starts all
  # image services and stops the container if the Coder agent exits.
  command = [
    "/command/s6-setuidgid",
    "dev",
    "/usr/bin/env",
    "HOME=/home/dev",
    "USER=dev",
    "/bin/sh",
    "-c",
    replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal"),
  ]

  env = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = "/workspace"
    volume_name    = docker_volume.workspace.name
  }

  volumes {
    container_path = "/home/dev"
    volume_name    = docker_volume.home.name
  }
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code"
  display_name = "VS Code"
  url          = "http://localhost:8080/code/"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8080/health"
    interval  = 10
    threshold = 3
  }
}
```

The Coder provisioner needs its normal access to the target Docker daemon. The
workspace container itself does not need the Docker socket, privileged mode, or
extra Linux capabilities.

## Access modes

### Browser IDE

Coder routes to code-server through its authenticated app proxy. Because the app
is owner-only, code-server can remain passwordless in this mode. Set `PASSWORD`
or `HASHED_PASSWORD` as defense in depth when your policy requires it.

Alternatively, if your Coder instance supports port forwarding, access code-server directly through the Caddy proxy:

```
https://your-coder-instance/workspace-name/apps/code/
```

### Terminal

```bash
coder ssh <workspace-name>
```

### Port forwarding

Forward the workspace proxy port to your local machine:

```bash
coder port-forward <workspace-name> --tcp 8080:8080
```

Then access locally:
- `http://localhost:8080/code/` — code-server
- `http://localhost:8080/lab` — JupyterLab
- `http://localhost:8080/status` — workspace status

## Single-port model

The Caddy proxy on port 8080 is the only port you need to expose from the Coder template. All services are accessible via path-based routing through that single port.

This simplifies Coder template configuration — one port, multiple services, no hostname dependencies.

## Customization

Choose the image flavor per workspace:

```hcl
resource "docker_image" "workspace" {
  name = "ghcr.io/jo-cube/workspace:full"
}
```

Service defaults come from the image flavor. Use `lab` or `full` for JupyterLab.

## Licensing

This repository does not distribute or modify Coder. It only documents how to
use these images from a Coder template. Coder Community is self-hosted and
licensed under AGPLv3; some enterprise features require a Premium license. Check
[Coder's current licensing documentation](https://coder.com/docs/admin/licensing)
against your organization's requirements before deployment.
