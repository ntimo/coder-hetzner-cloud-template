terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.11.0"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.41.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "coder" {
}

variable "hcloud_token" {
  description = <<EOF
Coder requires a Hetzner Cloud token to provision workspaces.
EOF
  sensitive   = true
  validation {
    condition     = length(var.hcloud_token) == 64
    error_message = "Please provide a valid Hetzner Cloud API token."
  }
}

data "coder_parameter" "instance_location" {
  name        = "Location"
  default     = "fsn1"
  type        = "string"
  mutable     = false

  option {
    name = "Nuremberg"
    value = "nbg1"
    icon = "/emojis/1f1e9-1f1ea.png"
  }

  option {
    name = "Falkenstein"
    value = "fsn1"
    icon = "/emojis/1f1e9-1f1ea.png"
  }

  option {
    name = "Helsinki"
    value = "hel1"
    icon = "/emojis/1f1eb-1f1ee.png"
  }

  option {
    name = "Hillsboro"
    value = "hil"
    icon = "/emojis/1f1fa-1f1f8.png"
  }

  option {
    name = "Ashburn"
    value = "ash"
    icon = "/emojis/1f1fa-1f1f8.png"
  }
}

data "coder_parameter" "instance_type" {
  name        = "Instance Type"
  default     = "cpx11"
  type        = "string"
  mutable     = true
  description = "ARM64 is only available in Falkenstein (fsn1) region."

  option {
    name = "cpx11 AMD ADM64 VCPUS 2, RAM 2GB"
    value = "cpx11"
  }

  option {
    name = "cpx21 AMD ADM64 VCPUS 3, RAM 4GB"
    value = "cpx21"
  }

  option {
    name = "cpx31 AMD ADM64 VCPUS 4, RAM 8GB"
    value = "cpx31"
  }

  option {
    name = "cpx41 AMD ADM64 VCPUS 8, RAM 16GB"
    value = "cpx41"
  }

  option {
    name = "cpx51 AMD ADM64 VCPUS 16, RAM 32GB"
    value = "cpx51"
  }

  option {
    name = "cax11 Ampere ARM64 VCPUS 2, RAM 4GB"
    value = "cax11"
  }

  option {
    name = "cax21 Ampere ARM64 VCPUS 4, RAM 8GB"
    value = "cax21"
  }

  option {
    name = "cax31 Ampere ARM64 VCPUS 8, RAM 16GB"
    value = "cax31"
  }

  option {
    name = "cax41 Ampere ARM64 VCPUS 16, RAM 32GB"
    value = "cax41"
  }
}

data "coder_parameter" "instance_os" {
  name        = "OS"
  default     = "fedora-38"
  type        = "string"
  mutable     = true

  option {
    name = "Fedora 38"
    value = "fedora-38"
    icon  = "/icon/fedora.svg"
  }

  option {
    name = "AlmaLinux 9"
    value = "alma-9"
    icon  = "https://upload.wikimedia.org/wikipedia/commons/1/13/AlmaLinux_Icon_Logo.svg"
  }

  option {
    name = "Ubuntu 22.04"
    value = "ubuntu-22.04"
    icon  = "/icon/ubuntu.svg"
  }

  option {
    name = "Debian 12"
    value = "debian-12"
    icon  = "/icon/debian.svg"
  }
}

data "coder_parameter" "volume_size" {
  name        = "volume_size"
  description = "Disk Size in GB"
  default     = 10
  type        = "number"
  mutable     = true
  validation {
    min       = 10
    max       = 250
    monotonic = "increasing"
  }
}

data "coder_parameter" "dotfiles_uri" {
  name        = "Dotfiles URL"
  description = "Optional"
  default     = ""
  type        = "string"
  mutable     = true
}

data "coder_parameter" "code_server" {
  name        = "code_server"
  description = "Should Code-server be installed?"
  type        = "bool"
  default     = true
  mutable     = true
}

data "coder_workspace" "me" {
}

resource "coder_agent" "dev" {
  arch = strcontains(data.coder_parameter.instance_type.value, "cax") ? "arm64" : "amd64"
  os   = "linux"
  startup_script = data.coder_parameter.dotfiles_uri.value != "" ? "/tmp/coder*/coder dotfiles -y ${data.coder_parameter.dotfiles_uri.value}" : null
}

resource "coder_app" "code-server" {
  count         = data.coder_parameter.code_server.value ? 1 : 0
  agent_id      = coder_agent.dev.id
  display_name  = "VS Code"
  slug          = "code-server"
  icon          = "/icon/code.svg"
  url           = "http://127.0.0.1:13337"
  subdomain     = false
  share         = "owner"
  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

# Generate a dummy ssh key that is not accessible so Hetzner cloud does not spam the admin with emails.
resource "tls_private_key" "rsa_4096" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "hcloud_ssh_key" "root" {
  name       = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-root"
  public_key = tls_private_key.rsa_4096.public_key_openssh
}

resource "hcloud_server" "root" {
  count       = data.coder_workspace.me.start_count
  name        = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-root"
  server_type = data.coder_parameter.instance_type.value
  location    = data.coder_parameter.instance_location.value
  image       = data.coder_parameter.instance_os.value
  ssh_keys    = [hcloud_ssh_key.root.id]
  user_data   = templatefile("cloud-config.yaml.tftpl", {
    username          = data.coder_workspace.me.owner
    volume_path       = "/dev/disk/by-id/scsi-0HC_Volume_${hcloud_volume.root.id}"
    init_script       = base64encode(coder_agent.dev.init_script)
    coder_agent_token = coder_agent.dev.token
    code_server_setup = data.coder_parameter.code_server.value
  })
}

resource "hcloud_volume" "root" {
  name         = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-root"
  format       = "ext4"
  size         = data.coder_parameter.volume_size.value
  location     = data.coder_parameter.instance_location.value
}

resource "hcloud_volume_attachment" "root" {
  count     = data.coder_workspace.me.start_count
  volume_id = hcloud_volume.root.id
  server_id = hcloud_server.root[count.index].id
  automount = false
}

resource "hcloud_firewall" "root" {
  name = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-root"
  rule {
    direction = "in"
    protocol  = "icmp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}

resource "hcloud_firewall_attachment" "root_fw_attach" {
    count = data.coder_workspace.me.start_count
    firewall_id = hcloud_firewall.root.id
    server_ids  = [hcloud_server.root[count.index].id]
}
