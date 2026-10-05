# bootstrap

`post-install.sh` prepares a freshly installed Proxmox VE 9 host. It runs once, as
root, and is safe to run again.

What it does:

- Disables the enterprise repositories and enables `pve-no-subscription`.
- Removes the "No valid subscription" dialog from the web UI.
- Disables suspend, and lid-close handling if the host is a laptop.
- Installs baseline packages, including CPU microcode and `unattended-upgrades`.
- Reports whether the IOMMU is active. This step changes nothing.

Every file it modifies is backed up next to the original as `.bak.<timestamp>`. It
does not reboot, upgrade the system, or touch storage or networking.

## Run

```bash
scp -r bootstrap root@<proxmox-address>:/root/
ssh root@<proxmox-address>
cd /root/bootstrap
./post-install.sh --dry-run
./post-install.sh
reboot
```

The reboot loads the new CPU microcode.

Run the script again after every Proxmox upgrade: `pve-manager` updates restore the
subscription dialog.
