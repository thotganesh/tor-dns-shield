#!/usr/bin/env bash
# Stops and removes tor-dns-shield containers. Asks before deleting data and files.
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${1:-}" ]]; then DIR="$1"
elif [[ -f "$HERE/docker-compose.yml" ]]; then DIR="$HERE"
else DIR="${TDS_DIR:-/opt/tor-dns-shield}"; fi
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
[[ -f "$DIR/docker-compose.yml" ]] || { echo "no installation found in $DIR" >&2; exit 1; }

read -r -p "Stop and remove all tor-dns-shield containers? [y/N] " a </dev/tty
[[ "${a,,}" == y* ]] || exit 0
(cd "$DIR" && docker compose down --remove-orphans)

read -r -p "Also delete volumes (Tor state, AdGuard config and stats)? [y/N] " a </dev/tty
if [[ "${a,,}" == y* ]]; then (cd "$DIR" && docker compose down -v); fi

read -r -p "Delete $DIR? [y/N] " a </dev/tty
if [[ "${a,,}" == y* ]]; then rm -rf -- "$DIR"; fi
echo "Done. Remember to point your devices back to a working DNS server."
