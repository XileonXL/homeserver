# opentofu

Creates the guests on the Proxmox node with the `bpg/proxmox` provider. It stops
there: everything inside a guest is configured by [Ansible](../ansible/README.md).

Everything lives in `envs/homeserver/`. Addresses, the node name, the containers and the
VM size are variables in `variables.tf`; adding a container is one more entry in
`containers`.

Home Assistant OS is an appliance: no cloud-init and no SSH. OpenTofu does not set
its IP address; the `haos_network` Ansible role does. The VM is protected with
`prevent_destroy` because its disk holds data this repository cannot regenerate.

## Prerequisites

1. `ansible-playbook site.yml --limit proxmox` in `ansible/`. It creates the API
   token, writes it to the git-ignored `.env` at the repository root, and writes
   `envs/homeserver/lxc_template.auto.tfvars.json`. The `haos_image` role writes
   `envs/homeserver/haos_image.auto.tfvars.json`.
2. The SSH public key at `~/.ssh/id_ed25519_personal_homeserver.pub`, or set
   `ssh_public_key_path`.

## Usage

```bash
cd envs/homeserver
set -a; source ../../../.env; set +a
tofu init
tofu validate
tofu plan
```

The API token is read from `PROXMOX_VE_API_TOKEN` and is never a OpenTofu variable.

## State

Local backend: one operator, no CI. `terraform.tfstate` can hold secrets in plaintext
and must never be committed.
