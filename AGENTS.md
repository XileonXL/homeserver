# Agent instructions

Infrastructure as code for a single-node home server on Proxmox VE. See `README.md`
for what it does and how it is used.

## Scope

The server runs a house: DNS filtering, remote access, home automation. The test for
adding anything is whether it delivers a real benefit. It is not a Kubernetes lab
and not a general-purpose NAS.

## Rules

- **No manual commands on the machines.** Every change goes through Ansible, or
  through `bootstrap/` for the one-off host script. Diagnostics and steps in
  third-party web consoles are the exception.
- **Keep it reusable.** Site-specific values (addresses, node name, sizes) are
  variables with defaults, never literals inside tasks or resources. Roles must work
  on any Debian-family host.
- **Nothing speculative.** No placeholder roles, groups or variables for things that
  do not exist yet.
- **Secrets** come from the environment, loaded from the git-ignored `.env` at the
  repository root. Never write a secret to a tracked file, and use `no_log` on any
  task that carries one. `.env.example` lists the variables.
- **Terraform**: `bpg/proxmox` only. Local state, never committed. Never
  run `terraform apply`; plan, validate and lint only.
- **Ansible**: fully qualified module names, accurate `changed` reporting, and check
  mode must not fail on a host where the software is not installed yet.
- **Decisions** are recorded in `docs/decisions.md`. Update it when one changes.
- All file content in English. READMEs stay short.

## Layout

```
bootstrap/   host post-install script
ansible/     configuration of the host and the containers
terraform/   creation of the guests
docs/        install guide, network plan and decisions
```

## Things that are easy to get wrong

- LXC for light services, a VM for anything that needs its own kernel.
  Home Assistant OS is an appliance in a VM and is not managed by Ansible.
- Tailscale runs on the Proxmox host as a subnet router, not as a client per guest.
- Never configure a secondary DNS server next to Pi-hole. Resolvers use secondaries
  opportunistically, so filtering leaks and outages go unnoticed.
- A full LVM thin pool corrupts guests. Anything that grows without bound, such as
  media, goes on a separate disk.
- Changing a container's template or injected SSH key forces Terraform to replace it;
  both are in `ignore_changes` on purpose.

## Verification

- Shell: `shellcheck` and `bash -n`.
- Ansible: `ansible-playbook site.yml --syntax-check` and `ansible-lint`, from
  `ansible/`.
- Terraform: `terraform fmt -check`, `terraform validate` and `tflint`, from
  `terraform/envs/homelab/`.
