# vps-optimize-Mariovz19

Audit a Linux VPS over SSH and optionally add swap to relieve RAM pressure.
Swap provides a safety buffer, not additional physical RAM, and can slow workloads
when heavily used. Investigate large processes and application limits first.

## Requirements

- Local Bash and OpenSSH, with an authorized SSH key and a verified host key.
- Remote Linux with Bash, procps (`free`, `ps`, `uptime`), util-linux
  (`swapon`, `mkswap`), and standard coreutils.
- Swap creation requires root or non-interactive sudo permission. Containers or
  some filesystems may not support swap files.

## Usage

```sh
# Read-only audit: load, RAM, swap, root disk usage, and largest processes.
bash vps-optimize.sh user@your-vps

# Explicitly request 1024 MiB of disk-backed swap after the audit.
bash vps-optimize.sh --swap-size 1024 user@your-vps
```

SSH aliases from `~/.ssh/config` are supported; configure custom ports and keys
there. The script uses non-interactive authentication, preserves SSH host-key
checks, and returns a nonzero status on connection or operation failures.
Run it only against systems you administer.

## Swap safeguards and cleanup

The default audit makes no configuration changes. The optional operation:

- Does nothing if any swap is already active.
- Accepts 128–65536 MiB and requires at least 1024 MiB of disk space left over.
- Creates only `/swapfile-vps-optimize`, with owner-only permissions; existing
  files or symlinks are never overwritten.
- Removes the newly created file if allocation or activation fails.
- Does not drop caches, kill processes, disable services, change kernel settings,
  or edit `/etc/fstab`.

Swap activation is temporary and does not survive reboot. The file remains on
disk after reboot. To undo the operation, first ensure enough RAM is available
to page swap contents back into memory, then run on the VPS:

```sh
sudo swapoff /swapfile-vps-optimize && sudo rm -- /swapfile-vps-optimize
```

After a reboot, if that file is no longer active swap, remove it with
`sudo rm -- /swapfile-vps-optimize` before requesting new swap.
Back up important data before making resource changes. No VPS credentials are
stored in this repository.