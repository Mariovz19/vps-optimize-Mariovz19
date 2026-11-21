#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'HELP'
Usage: bash vps-optimize.sh [--swap-size MiB] [user@]host

Audit a Linux VPS over SSH without changing its configuration.
  --swap-size MiB  Explicitly add 128–65536 MiB of temporary disk-backed swap
                   if no swap is active. Requires root or passwordless sudo.
  -h, --help       Show this help

Uses your SSH configuration and keys. Never disables host-key verification.
HELP
}

swap_mib=0
target=
while (($#)); do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --swap-size)
            if (($# < 2)) || [[ ! $2 =~ ^[1-9][0-9]{2,4}$ ]]; then
                echo "Error: --swap-size requires an integer from 128 to 65536 MiB." >&2
                exit 2
            fi
            swap_mib=$2
            if ((swap_mib < 128 || swap_mib > 65536)); then
                echo "Error: --swap-size must be between 128 and 65536 MiB." >&2
                exit 2
            fi
            shift 2
            ;;
        -*)
            echo "Error: unknown option: $1" >&2
            exit 2
            ;;
        *)
            if [[ -n $target || ! $1 =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.@:-]*$ ]]; then
                echo "Error: supply one SSH host or user@host (SSH aliases are supported)." >&2
                exit 2
            fi
            target=$1
            shift
            ;;
    esac
done

if [[ -z $target ]]; then
    usage >&2
    exit 2
fi

ssh -o BatchMode=yes -o ConnectTimeout=15 -- "$target" bash -s -- "$swap_mib" <<'REMOTE'
set -euo pipefail
swap_mib=$1

if [[ $(uname -s) != Linux ]]; then
    echo "Error: this tool requires a Linux VPS." >&2
    exit 1
fi

printf '\n== System and load ==\n'
uname -sr
uptime
printf '\n== RAM and swap (available RAM accounts for reclaimable cache) ==\n'
free -h
printf '\n== Root filesystem ==\n'
df -h /
printf '\n== Active swap ==\n'
swapon --show
printf '\n== Largest processes by resident RAM (RSS in KiB) ==\n'
ps -eo pid,user,comm,rss --sort=-rss | sed -n '1,11p'

if ((swap_mib == 0)); then
    printf '\nAudit only: no changes made. Investigate large processes before adding swap.\n'
    exit 0
fi

privilege=()
if ((EUID != 0)); then
    privilege=(sudo -n)
fi
"${privilege[@]}" bash -s -- "$swap_mib" <<'SWAP'
set -euo pipefail
swap_mib=$1
swap_file=/swapfile-vps-optimize

if [[ $(awk '/^SwapTotal:/ {print $2}' /proc/meminfo) != 0 ]]; then
    echo "Swap is already active; leaving it unchanged."
    exit 0
fi

for command in dd mkswap swapon df awk chmod rm; do
    command -v "$command" >/dev/null || {
        echo "Error: required command not found: $command" >&2
        exit 1
    }
done

available_mib=$(df -Pm / | awk 'NR == 2 {print $4}')
if [[ ! $available_mib =~ ^[0-9]+$ ]] || ((available_mib < swap_mib + 1024)); then
    echo "Error: insufficient disk space; at least 1024 MiB must remain free." >&2
    exit 1
fi

umask 077
if ! (set -o noclobber; : > "$swap_file"); then
    echo "Error: refusing to overwrite $swap_file." >&2
    exit 1
fi
trap 'rm -f -- "$swap_file"' EXIT
chmod 600 "$swap_file"
dd if=/dev/zero of="$swap_file" bs=1M count="$swap_mib" status=none
mkswap "$swap_file"
swapon "$swap_file"
trap - EXIT
printf '\nTemporary swap enabled at %s. No boot configuration was changed.\n' "$swap_file"
SWAP

printf '\n== RAM and swap after requested operation ==\n'
free -h
swapon --show
REMOTE
