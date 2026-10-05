#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034  # kept for consistency with the standard script layout, unused otherwise
readonly SCRIPT_DIR
SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_NAME

readonly PVE_NO_SUB_SOURCES="/etc/apt/sources.list.d/proxmox.sources"
readonly PVE_ENTERPRISE_SOURCES="/etc/apt/sources.list.d/pve-enterprise.sources"
readonly CEPH_ENTERPRISE_SOURCES="/etc/apt/sources.list.d/ceph.sources"
readonly DEBIAN_SOURCES="/etc/apt/sources.list.d/debian.sources"
readonly PVE_NO_SUB_CONTENT="Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg"
readonly WIDGET_TOOLKIT_JS="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
readonly LOGIND_DROPIN_DIR="/etc/systemd/logind.conf.d"
readonly LOGIND_DROPIN="${LOGIND_DROPIN_DIR}/10-homeserver-lid.conf"
readonly NETWORK_CHECK_URL="http://download.proxmox.com/debian/pve/dists/trixie/Release"
readonly PACKAGES=(vim htop curl git ethtool lm-sensors unattended-upgrades)

DRY_RUN=false
CHANGES_LOG=()

log_info()  { printf '[INFO]  %s\n' "$*"; }
log_warn()  { printf '[WARN]  %s\n' "$*" >&2; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Run once, as root, on a freshly installed Proxmox VE 9 node. Idempotent and
safe to re-run. Prepares the host for Terraform/Ansible-driven provisioning.

Options:
  -h, --help      Show this help and exit
  -n, --dry-run   Print actions without making any changes
EOF
}

record_change() {
  local message="${1}"
  CHANGES_LOG+=("${message}")
}

preflight() {
  log_info "Running preflight checks..."

  if [[ "${EUID}" -ne 0 ]]; then
    log_error "This script must be run as root (current EUID=${EUID})."
    exit 1
  fi

  if ! command -v pveversion &>/dev/null; then
    log_error "pveversion not found. This does not look like a Proxmox VE host."
    exit 1
  fi

  local pve_version pve_major os_codename
  pve_version="$(pveversion 2>/dev/null || true)"
  pve_major="${pve_version#pve-manager/}"
  pve_major="${pve_major%%.*}"
  os_codename="$(grep -E '^VERSION_CODENAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"
  if [[ "${pve_major}" != "9" || "${os_codename}" != "trixie" ]]; then
    log_error "This script targets Proxmox VE 9 (Debian trixie only); found pve-manager major '${pve_major}', codename '${os_codename}'."
    exit 1
  fi

  if command -v curl &>/dev/null; then
    if ! curl --silent --fail --max-time 5 --head "${NETWORK_CHECK_URL}" &>/dev/null; then
      log_error "Network reachability check against ${NETWORK_CHECK_URL} failed."
      exit 1
    fi
  else
    log_warn "curl not found; falling back to /dev/tcp check against download.proxmox.com:80."
    if ! timeout 5 bash -c 'exec 3<>/dev/tcp/download.proxmox.com/80' 2>/dev/null; then
      log_error "Network reachability fallback check failed (no curl, TCP connect failed)."
      exit 1
    fi
  fi

  log_info "Preflight checks passed."
}

backup_file() {
  local file="${1}"
  local backup
  backup="${file}.bak.$(date +%Y%m%d%H%M%S)"

  if "${DRY_RUN}"; then
    log_info "[DRY-RUN] would back up ${file} to ${backup}"
    return 0
  fi

  cp --preserve=all "${file}" "${backup}"
  log_info "Backed up ${file} to ${backup}"
}

# Print a deb822 file with every stanza forced to "Enabled: no". An existing
# Enabled: field is replaced (duplicates dropped), otherwise one is appended to
# the stanza. Paragraphs without a Types: field (e.g. header comments) are kept
# as they are.
deb822_disable() {
  awk '
    function flush(   i, seen, has_types) {
      if (n == 0) return
      has_types = 0
      seen = 0
      for (i = 1; i <= n; i++) if (lines[i] ~ /^[Tt]ypes[[:space:]]*:/) has_types = 1
      for (i = 1; i <= n; i++) {
        if (has_types && lines[i] ~ /^[Ee]nabled[[:space:]]*:/) {
          if (!seen) print "Enabled: no"
          seen = 1
        } else {
          print lines[i]
        }
      }
      if (has_types && !seen) print "Enabled: no"
      n = 0
    }
    /^[[:space:]]*$/ { flush(); print; next }
    { lines[++n] = $0 }
    END { flush() }
  ' "${1}"
}

# Print a deb822 file with non-free-firmware appended to every Components: line
# that lacks it. All other bytes are left as they are.
deb822_add_firmware() {
  awk '
    /^[Cc]omponents[[:space:]]*:/ && $0 !~ /(^|[[:space:]])non-free-firmware([[:space:]]|$)/ {
      sub(/[[:space:]]+$/, "")
      print $0 " non-free-firmware"
      next
    }
    { print }
  ' "${1}"
}

configure_repositories() {
  log_info "Configuring APT repositories..."

  # The enterprise repo files are disabled in place (Enabled: no), not deleted or
  # moved: Proxmox's own tooling (and future pve-manager upgrades) expects these
  # files to exist, and keeping them auditable/reversible is preferable to
  # removing them. Backups use a .bak.<timestamp> suffix, which apt ignores
  # (only .list/.sources files in sources.list.d are parsed).
  local enterprise_sources new_content
  for enterprise_sources in "${PVE_ENTERPRISE_SOURCES}" "${CEPH_ENTERPRISE_SOURCES}"; do
    if [[ ! -f "${enterprise_sources}" ]]; then
      log_info "${enterprise_sources} does not exist, nothing to disable."
      continue
    fi

    if cmp -s "${enterprise_sources}" <(deb822_disable "${enterprise_sources}"); then
      log_info "${enterprise_sources} already disabled (all stanzas have Enabled: no)."
      continue
    fi

    if "${DRY_RUN}"; then
      log_info "[DRY-RUN] would set 'Enabled: no' in every stanza of ${enterprise_sources}"
      record_change "would disable enterprise repo: ${enterprise_sources}"
      continue
    fi

    backup_file "${enterprise_sources}"
    # Sentinel keeps trailing newlines, which command substitution would strip.
    new_content="$(deb822_disable "${enterprise_sources}"; printf x)"
    printf '%s' "${new_content%x}" >"${enterprise_sources}"
    log_info "Disabled enterprise repo: ${enterprise_sources}"
    record_change "disabled enterprise repo: ${enterprise_sources}"
  done

  # CPU microcode packages live in Debian's non-free-firmware component. debian.sources
  # is edited in place with a backup; its other content is left untouched.
  if [[ ! -f "${DEBIAN_SOURCES}" ]]; then
    log_warn "${DEBIAN_SOURCES} not found, cannot enable non-free-firmware (the microcode package install may fail)."
  elif cmp -s "${DEBIAN_SOURCES}" <(deb822_add_firmware "${DEBIAN_SOURCES}"); then
    log_info "${DEBIAN_SOURCES} already has non-free-firmware in all stanzas."
  elif "${DRY_RUN}"; then
    log_info "[DRY-RUN] would add non-free-firmware to Components: in ${DEBIAN_SOURCES}"
    record_change "would enable non-free-firmware: ${DEBIAN_SOURCES}"
  else
    backup_file "${DEBIAN_SOURCES}"
    new_content="$(deb822_add_firmware "${DEBIAN_SOURCES}"; printf x)"
    printf '%s' "${new_content%x}" >"${DEBIAN_SOURCES}"
    log_info "Enabled non-free-firmware in ${DEBIAN_SOURCES}"
    record_change "enabled non-free-firmware: ${DEBIAN_SOURCES}"
  fi

  if [[ -f "${PVE_NO_SUB_SOURCES}" ]] && [[ "$(<"${PVE_NO_SUB_SOURCES}")" == "${PVE_NO_SUB_CONTENT}" ]]; then
    log_info "${PVE_NO_SUB_SOURCES} already contains the expected pve-no-subscription stanza."
    return 0
  fi

  if "${DRY_RUN}"; then
    log_info "[DRY-RUN] would write ${PVE_NO_SUB_SOURCES} with the pve-no-subscription stanza (suite trixie)"
    record_change "would enable pve-no-subscription repo: ${PVE_NO_SUB_SOURCES}"
    return 0
  fi

  if [[ -f "${PVE_NO_SUB_SOURCES}" ]]; then
    backup_file "${PVE_NO_SUB_SOURCES}"
  fi

  printf '%s\n' "${PVE_NO_SUB_CONTENT}" >"${PVE_NO_SUB_SOURCES}"
  log_info "Enabled pve-no-subscription repo at ${PVE_NO_SUB_SOURCES}"
  record_change "enabled pve-no-subscription repo: ${PVE_NO_SUB_SOURCES}"
}

patch_subscription_nag() {
  log_info "Checking subscription nag patch state..."

  if [[ ! -f "${WIDGET_TOOLKIT_JS}" ]]; then
    log_warn "${WIDGET_TOOLKIT_JS} not found, skipping nag patch."
    return 0
  fi

  # Well-known community patch (not invented here): the widget toolkit's
  # checked_command() gates the "No valid subscription" Ext.Msg.show popup on
  # `res.data.status.toLowerCase() !== 'active'`. Rewriting that comparison to
  # `=== undefined` makes it always false (toLowerCase() returns a string), so
  # the dialog never fires. The file lives in a package shipped by Proxmox, so
  # every package update reverts it and this function must be re-run afterward.
  # The exact expression can vary between versions, so only the tail is matched.
  if grep -qF ".data.status.toLowerCase() === undefined" "${WIDGET_TOOLKIT_JS}"; then
    log_info "Subscription nag already patched, skipping."
    return 0
  fi

  if ! grep -qE "\.data\.status\.toLowerCase\(\) !== 'active'" "${WIDGET_TOOLKIT_JS}"; then
    log_warn "Subscription nag expression not found in ${WIDGET_TOOLKIT_JS} (file layout may have changed), skipping nag patch."
    return 0
  fi

  if "${DRY_RUN}"; then
    log_info "[DRY-RUN] would patch ${WIDGET_TOOLKIT_JS} to suppress the subscription nag"
    record_change "would patch subscription nag dialog: ${WIDGET_TOOLKIT_JS}"
    return 0
  fi

  backup_file "${WIDGET_TOOLKIT_JS}"
  sed -i -E "s/(\.data\.status\.toLowerCase\(\)) !== 'active'/\1 === undefined/g" "${WIDGET_TOOLKIT_JS}"
  log_info "Patched subscription nag dialog in ${WIDGET_TOOLKIT_JS}"
  record_change "patched subscription nag dialog: ${WIDGET_TOOLKIT_JS} (reverted by pve-manager updates)"
}

configure_power() {
  log_info "Configuring lid/suspend behavior..."

  local -a settings=(
    "HandleLidSwitch=ignore"
    "HandleLidSwitchExternalPower=ignore"
    "HandleLidSwitchDocked=ignore"
  )

  # Debian 13 does not ship /etc/systemd/logind.conf (defaults live under
  # /usr/lib/systemd), so the settings go in a drop-in under logind.conf.d/.
  local desired current=""
  desired="$(printf '[Login]\n'; printf '%s\n' "${settings[@]}")"
  if [[ -f "${LOGIND_DROPIN}" ]]; then
    current="$(<"${LOGIND_DROPIN}")"
  fi

  if [[ "${current}" == "${desired}" ]]; then
    log_info "${LOGIND_DROPIN} already had the desired lid-switch settings."
  elif "${DRY_RUN}"; then
    log_info "[DRY-RUN] would write ${LOGIND_DROPIN} with: ${settings[*]}"
    record_change "would write lid-switch settings to ${LOGIND_DROPIN}"
  else
    mkdir -p "${LOGIND_DROPIN_DIR}"
    printf '%s\n' "${desired}" >"${LOGIND_DROPIN}"
    log_info "Wrote ${LOGIND_DROPIN}, restarting systemd-logind."
    systemctl restart systemd-logind
    record_change "wrote lid-switch handling to ${LOGIND_DROPIN} and restarted systemd-logind"
  fi

  local -a sleep_targets=(sleep.target suspend.target hibernate.target hybrid-sleep.target)
  local target
  for target in "${sleep_targets[@]}"; do
    if "${DRY_RUN}"; then
      if [[ "$(systemctl is-enabled "${target}" 2>/dev/null || true)" == "masked" ]]; then
        log_info "${target} already masked."
      else
        log_info "[DRY-RUN] would mask ${target}"
        record_change "would mask ${target}"
      fi
      continue
    fi
    # systemctl mask is idempotent: masking an already-masked unit is not an error.
    # Only record it as a change when the unit was not already masked, so that a
    # second run reports an empty change set.
    if [[ "$(systemctl is-enabled "${target}" 2>/dev/null || true)" == "masked" ]]; then
      continue
    fi
    systemctl mask "${target}"
    record_change "masked ${target}"
  done
  log_info "Sleep/suspend/hibernate targets masked."
}

microcode_package() {
  if grep -q AuthenticAMD /proc/cpuinfo; then
    printf 'amd64-microcode\n'
  else
    printf 'intel-microcode\n'
  fi
}

install_packages() {
  log_info "Installing baseline packages..."

  local -a packages
  packages=("${PACKAGES[@]}" "$(microcode_package)")

  if "${DRY_RUN}"; then
    log_info "[DRY-RUN] would run: apt-get update"
    log_info "[DRY-RUN] would run: apt-get install -y ${packages[*]}"
    record_change "would install packages: ${packages[*]}"
    return 0
  fi

  apt-get update
  apt-get install -y "${packages[@]}"
  record_change "installed packages: ${packages[*]}"

  # NOTE: enabling unattended-upgrades on a hypervisor is a judgement call.
  # This function only installs the package with its packaged defaults.
  # Review /etc/apt/apt.conf.d/50unattended-upgrades manually afterward and
  # restrict it to security-only origins if unattended kernel/pve-manager
  # upgrades on a hypervisor are not desired.
  log_info "unattended-upgrades installed; review /etc/apt/apt.conf.d/50unattended-upgrades manually."
}

report_iommu_status() {
  log_info "Checking IOMMU/VT-d availability (informational only, no changes made)..."

  local vmx_count
  vmx_count="$(grep -c -E '^flags.*[[:space:]](vmx|svm)([[:space:]]|$)' /proc/cpuinfo || true)"

  local dmar_output
  if dmar_output="$(dmesg 2>/dev/null | grep -i -e DMAR -e IOMMU || true)" && [[ -n "${dmar_output}" ]]; then
    log_info "dmesg contains DMAR/IOMMU references:"
    printf '%s\n' "${dmar_output}"
  else
    log_info "No DMAR/IOMMU references found in dmesg (this can also mean the dmesg buffer was cleared or IOMMU is disabled in firmware/kernel cmdline)."
  fi

  printf '\n'
  if [[ "${vmx_count}" -gt 0 ]]; then
    printf 'IOMMU report: virtualization flag (vmx/svm) present on %s CPU thread(s); check dmesg output above for actual IOMMU activation.\n' "${vmx_count}"
  else
    printf 'IOMMU report: no vmx/svm flag in /proc/cpuinfo; virtualization extensions may be disabled in firmware.\n'
  fi
  printf 'This check is informational, for device passthrough planning.\n'
  printf 'This script does NOT modify grub or the kernel cmdline.\n\n'
}

print_summary() {
  local prefix=""
  "${DRY_RUN}" && prefix="[DRY-RUN] "

  printf '\n=== %spost-install summary ===\n' "${prefix}"

  if [[ "${#CHANGES_LOG[@]}" -eq 0 ]]; then
    printf 'No changes were made (or would be made); system already in desired state.\n'
  else
    local entry
    for entry in "${CHANGES_LOG[@]}"; do
      printf '  - %s\n' "${entry}"
    done
  fi

  printf '\nReminders:\n'
  printf '  - The subscription-nag patch (proxmoxlib.js) is reverted by every pve-manager\n'
  printf '    package update. Re-run this script (or at least patch_subscription_nag) after\n'
  printf '    any Proxmox upgrade.\n'
  printf '  - Suggested manual command to review and run separately: apt dist-upgrade\n'
  printf '    (this script never runs it automatically).\n'

  printf '  - CPU microcode is loaded early at boot via the initramfs: reboot this host\n'
  printf '    to apply it (this script never reboots).\n'

  printf '\nNext steps:\n'
  printf '  1. Configure this host with Ansible (see ansible/README.md).\n'
  printf '  2. Provision guests with Terraform (bpg/proxmox provider) against this node.\n'
  printf '\n'
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "${1}" in
      -h|--help)
        usage
        exit 0
        ;;
      -n|--dry-run)
        DRY_RUN=true
        shift
        ;;
      *)
        log_error "Unknown argument: ${1}"
        usage
        exit 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  if "${DRY_RUN}"; then
    log_info "Running in dry-run mode: no changes will be made."
  fi

  preflight
  configure_repositories
  patch_subscription_nag
  configure_power
  install_packages
  report_iommu_status
  print_summary
}

main "$@"
