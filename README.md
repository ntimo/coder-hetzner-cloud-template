# coder-hetzner-cloud-template
This repo contains a Terraform template for Coder https://github.com/coder/coder to setup a cloud instance as dev environment with or without vscode

This template will do the following:
- Creates a Hetzner Cloud instance
- Create a Hetzner Cloud volume
- Create a default block inbound firewall policy
- Add volumes and firewall policy to the instance
- Ask the user if code-server should be installed and if so installs it

