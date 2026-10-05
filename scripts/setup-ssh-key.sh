#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_NAME
readonly KEY_PATH="${HOME}/.ssh/id_ed25519_personal_homeserver"
readonly KEY_COMMENT="personal_homeserver"

log_info() { printf '[INFO]  %s\n' "$*"; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} <host> [user]

Creates the SSH key that Ansible and Terraform use (${KEY_PATH}),
if it does not exist yet, and authorises it on <host>.

Run it on the workstation, once per machine to be managed. It asks for the
remote password one last time.

Arguments:
  host    Address of the machine, for example 192.168.1.50
  user    Remote user (default: root)

Options:
  -h, --help   Show this help
EOF
}

main() {
  if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage >&2
    exit 1
  fi
  if [[ "${1}" == "-h" || "${1}" == "--help" ]]; then
    usage
    exit 0
  fi

  local host="${1}"
  local user="${2:-root}"

  local cmd
  for cmd in ssh ssh-keygen ssh-copy-id; do
    command -v "${cmd}" &>/dev/null || { log_error "${cmd} not found"; exit 1; }
  done

  if [[ -f "${KEY_PATH}" ]]; then
    log_info "Key already exists: ${KEY_PATH}"
  else
    log_info "Generating ${KEY_PATH}"
    ssh-keygen -t ed25519 -f "${KEY_PATH}" -C "${KEY_COMMENT}"
  fi

  log_info "Authorising the key for ${user}@${host}"
  ssh-copy-id -i "${KEY_PATH}.pub" "${user}@${host}"

  if ! ssh -i "${KEY_PATH}" -o IdentitiesOnly=yes -o PasswordAuthentication=no \
    "${user}@${host}" true; then
    log_error "Key login to ${user}@${host} failed after copying the key."
    exit 1
  fi
  log_info "Key login to ${user}@${host} works."
}

main "$@"
