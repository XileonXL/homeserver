# terraform

Creates the guests on the Proxmox node with the `bpg/proxmox` provider. It stops
there: everything inside a guest is configured by [Ansible](../ansible/README.md).

Everything lives in `envs/homelab/`. Addresses, the node name and the containers
themselves are variables in `variables.tf`; adding a container is one more entry in
`containers`. Only `pihole` is defined so far.

## Prerequisites

1. `ansible-playbook site.yml --limit proxmox` in `ansible/`. It creates the API
   token, writes it to the git-ignored `.env` at the repository root, and writes
   `envs/homelab/lxc_template.auto.tfvars.json`.
2. The SSH public key at `~/.ssh/id_ed25519_personal_homeserver.pub`, or set
   `ssh_public_key_path`.

## Usage

```bash
cd envs/homelab
set -a; source ../../../.env; set +a
terraform init
terraform validate
terraform plan
```

The API token is read from `PROXMOX_VE_API_TOKEN` and is never a Terraform variable.

## State

Local backend: one operator, no CI. `terraform.tfstate` can hold secrets in plaintext
and must never be committed.
