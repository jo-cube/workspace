# Coder integration

This image family is designed to work with self-hosted [Coder](https://coder.com) instances as workspace images.

## How it works

Coder provisions containers from workspace templates. These images provide:
- code-server as the browser IDE (Coder's built-in web terminal also works)
- A single proxy port (8080) for all web services
- SSH access via `coder ssh`

For app-level login, configure code-server with `PASSWORD` or `HASHED_PASSWORD` and JupyterLab with `JUPYTER_TOKEN`.

## Coder template example

Minimal Terraform template for a Docker-based Coder workspace:

```hcl
terraform {
  required_providers {
    coder = { source = "coder/coder" }
    docker = { source = "kreuzwerker/docker" }
  }
}

data "coder_workspace" "me" {}

resource "docker_image" "workspace" {
  name = "ghcr.io/jo-cube/workspace:platform"
}

resource "docker_container" "workspace" {
  name  = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
  image = docker_image.workspace.image_id

  volumes {
    host_path      = "/data/coder/${data.coder_workspace.me.id}/workspace"
    container_path = "/workspace"
  }

  volumes {
    host_path      = "/data/coder/${data.coder_workspace.me.id}/home"
    container_path = "/home/dev"
  }

  ports {
    internal = 8080
    external = 0  # dynamically assigned
  }
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code"
  display_name = "VS Code"
  url          = "http://localhost:8080/code/"
  subdomain    = false
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  dir  = "/workspace"
}
```

## Access modes

### Browser IDE

Coder routes to code-server through its built-in app proxy. The `coder_app` resource above registers code-server.

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
