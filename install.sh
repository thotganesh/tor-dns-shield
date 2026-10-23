#!/usr/bin/env bash
# tor-dns-shield installer
# Chain: clients -> [AdGuard Home] -> dnscrypt-proxy -> Tor (Snowflake/obfs4/direct) -> resolver
# Read this script before running it. It never pipes anything from the network into a shell.
set -Eeuo pipefail

VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------- defaults
INSTALL_DIR="${TDS_DIR:-/opt/tor-dns-shield}"
COUNTRIES="${TDS_COUNTRIES:-}"            # ISO codes, comma separated. Empty string = ask.
COUNTRIES_SET="${TDS_COUNTRIES+yes}"      # "yes" if provided (even if empty = none)
RESOLVER="${TDS_RESOLVER:-}"              # quad9 | adguard | cloudflare | custom
SERVER_NAMES="${TDS_SERVER_NAMES:-}"      # for custom: dnscrypt-proxy server names, comma separated
TRANSPORT="${TDS_TRANSPORT:-}"            # snowflake | direct | obfs4
OBFS4_FILE="${TDS_OBFS4_FILE:-}"
USE_ADGUARD="${TDS_ADGUARD:-}"            # yes | no
SNOWFLAKE_PROXY="${TDS_SNOWFLAKE_PROXY:-}"  # yes | no (asked, default yes)
SNOWFLAKE_CAPACITY="${TDS_SNOWFLAKE_CAPACITY:-10}"
LISTEN_IP="${TDS_LISTEN_IP:-127.0.0.1}"
DRY_RUN=0
NON_INTERACTIVE=0
SUBNET="172.28.0.0/24"
IP_TOR="172.28.0.10"
IP_DNSCRYPT="172.28.0.11"
IP_ADGUARD="172.28.0.12"

usage() {
  cat <<EOF
tor-dns-shield ${VERSION}

Usage: sudo ./install.sh [options]

  --countries fr,it        Exit-node countries to EXCLUDE (ISO 3166 alpha-2). Use "none" for no exclusion.
  --resolver NAME          quad9 (default) | adguard | cloudflare | custom
  --server-names a,b       dnscrypt-proxy server names (with --resolver custom)
  --transport MODE         snowflake (default) | direct | obfs4
  --obfs4-bridges-file F   File with obfs4 Bridge lines (with --transport obfs4)
  --adguard / --no-adguard Install AdGuard Home in front of dnscrypt-proxy
  --snowflake-proxy        Run a volunteer Snowflake proxy (DEFAULT: yes)
  --no-snowflake-proxy     Do not run a volunteer Snowflake proxy
  --capacity N             Max concurrent clients for the volunteer proxy (default 10)
  --listen-ip IP           Host IP where DNS (port 53) is published (default 127.0.0.1)
  --dir PATH               Install directory (default /opt/tor-dns-shield)
  --non-interactive        Never prompt; use flags/env/defaults
  --dry-run                Print generated files, change nothing, do not need Docker
  -h, --help               This help

Every option also exists as an environment variable (TDS_COUNTRIES, TDS_RESOLVER, ...).
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# ---------------------------------------------------------------- args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --countries) COUNTRIES="${2:?}"; COUNTRIES_SET=yes; shift 2 ;;
    --resolver) RESOLVER="${2:?}"; shift 2 ;;
    --server-names) SERVER_NAMES="${2:?}"; shift 2 ;;
    --transport) TRANSPORT="${2:?}"; shift 2 ;;
    --obfs4-bridges-file) OBFS4_FILE="${2:?}"; shift 2 ;;
    --adguard) USE_ADGUARD=yes; shift ;;
    --no-adguard) USE_ADGUARD=no; shift ;;
    --snowflake-proxy) SNOWFLAKE_PROXY=yes; shift ;;
    --no-snowflake-proxy) SNOWFLAKE_PROXY=no; shift ;;
    --capacity) SNOWFLAKE_CAPACITY="${2:?}"; shift 2 ;;
    --listen-ip) LISTEN_IP="${2:?}"; shift 2 ;;
    --dir) INSTALL_DIR="${2:?}"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown option: $1" ;;
  esac
done

# ---------------------------------------------------------------- UI helpers
INTERACTIVE=0
if [[ $NON_INTERACTIVE -eq 0 && -t 0 && -t 1 ]]; then INTERACTIVE=1; fi
HAVE_WHIPTAIL=0
if [[ $INTERACTIVE -eq 1 ]] && command -v whiptail >/dev/null 2>&1; then HAVE_WHIPTAIL=1; fi

# ask_yesno "question" default(yes|no) -> echoes yes|no
ask_yesno() {
  local q="$1" def="$2" ans
  if [[ $HAVE_WHIPTAIL -eq 1 ]]; then
    local flag=()
    [[ "$def" == "no" ]] && flag=(--defaultno)
    if whiptail "${flag[@]}" --title "tor-dns-shield" --yesno "$q" 24 76 3>&1 1>&2 2>&3; then echo yes; else echo no; fi
    return
  fi
  local hint="[Y/n]"; [[ "$def" == "no" ]] && hint="[y/N]"
  read -r -p "$q $hint " ans </dev/tty
  ans="${ans:-$def}"
  case "${ans,,}" in y|yes|s|si|sì|o|oui) echo yes ;; *) echo no ;; esac
}

# ask_choice "question" default opt1 opt2 ... -> echoes selected
ask_choice() {
  local q="$1" def="$2"; shift 2
  local opts=("$@") ans
  if [[ $HAVE_WHIPTAIL -eq 1 ]]; then
    local items=() o
    for o in "${opts[@]}"; do items+=("$o" ""); done
    whiptail --title "tor-dns-shield" --default-item "$def" --menu "$q" 18 72 "${#opts[@]}" "${items[@]}" 3>&1 1>&2 2>&3
    return
  fi
  echo "$q" >&2
  local i=1; for o in "${opts[@]}"; do echo "  $i) $o" >&2; i=$((i+1)); done
  read -r -p "Choice [$def]: " ans </dev/tty
  ans="${ans:-$def}"
  if [[ "$ans" =~ ^[0-9]+$ && "$ans" -ge 1 && "$ans" -le ${#opts[@]} ]]; then ans="${opts[$((ans-1))]}"; fi
  echo "$ans"
}

ask_text() {
  local q="$1" def="$2" ans
  if [[ $HAVE_WHIPTAIL -eq 1 ]]; then
    whiptail --title "tor-dns-shield" --inputbox "$q" 12 72 "$def" 3>&1 1>&2 2>&3
    return
  fi
  read -r -p "$q [$def]: " ans </dev/tty
  echo "${ans:-$def}"
}

# ---------------------------------------------------------------- questions
if [[ -z "$COUNTRIES_SET" ]]; then
  if [[ $INTERACTIVE -eq 1 ]]; then
    COUNTRIES="$(ask_text "Exit-node countries to EXCLUDE from Tor circuits.
ISO codes, comma separated (e.g. fr,it). Type 'none' for no exclusion.
Use the country whose DNS blocking orders you want to stay out of." "fr")"
  else
    COUNTRIES="none"
  fi
fi

if [[ -z "$RESOLVER" ]]; then
  if [[ $INTERACTIVE -eq 1 ]]; then
    RESOLVER="$(ask_choice "Upstream resolver (reached through Tor):" quad9 quad9 adguard cloudflare custom)"
  else
    RESOLVER="quad9"
  fi
fi

if [[ -z "$TRANSPORT" ]]; then
  if [[ $INTERACTIVE -eq 1 ]]; then
    TRANSPORT="$(ask_choice "How should Tor reach the network?
snowflake: hides Tor use from your ISP (slower start)
direct:    plain Tor (faster, ISP can see you use Tor)
obfs4:     private bridges you provide" snowflake snowflake direct obfs4)"
  else
    TRANSPORT="snowflake"
  fi
fi

if [[ -z "$USE_ADGUARD" ]]; then
  if [[ $INTERACTIVE -eq 1 ]]; then
    USE_ADGUARD="$(ask_yesno "Install AdGuard Home in front of dnscrypt-proxy?
(filtering, per-client stats, web UI on 127.0.0.1:3000)" yes)"
  else
    USE_ADGUARD="no"
  fi
fi

if [[ -z "$SNOWFLAKE_PROXY" ]]; then
  if [[ $INTERACTIVE -eq 1 ]]; then
    SNOWFLAKE_PROXY="$(ask_yesno "Help people in countries that block Tor?

Run a volunteer Snowflake proxy (recommended, enabled by default).
- It is NOT your own entry point: it only relays traffic for others.
- You are not an exit node: you see only encrypted traffic.
- It uses bandwidth, depending on how many people connect (up to ${SNOWFLAKE_CAPACITY} at once).
- Your IP address is visible to the people who connect through it.
- Check your hosting provider allows it. Skip it on metered or corporate links.

Press Enter to accept, or choose No." yes)"
  else
    SNOWFLAKE_PROXY="yes"
  fi
fi

# ---------------------------------------------------------------- validation
RESOLVER="${RESOLVER,,}"
TRANSPORT="${TRANSPORT,,}"
case "$RESOLVER" in quad9|adguard|cloudflare|custom) ;; *) die "invalid --resolver: $RESOLVER" ;; esac
case "$TRANSPORT" in snowflake|direct|obfs4) ;; *) die "invalid --transport: $TRANSPORT" ;; esac
[[ "$SNOWFLAKE_CAPACITY" =~ ^[0-9]+$ ]] || die "--capacity must be a number"
[[ "$LISTEN_IP" =~ ^[0-9.]+$ ]] || die "--listen-ip must be an IPv4 address"
USE_ADGUARD="${USE_ADGUARD:-no}"
SNOWFLAKE_PROXY="${SNOWFLAKE_PROXY:-yes}"

EXCLUDE_NODES=""
if [[ -n "$COUNTRIES" && "${COUNTRIES,,}" != "none" ]]; then
  IFS=',' read -r -a _cc <<<"${COUNTRIES// /}"
  _parts=()
  for c in "${_cc[@]}"; do
    c="${c,,}"
    [[ "$c" =~ ^[a-z]{2}$ ]] || die "invalid country code: '$c' (use ISO 3166 alpha-2, e.g. fr)"
    _parts+=("{${c}}")
  done
  EXCLUDE_NODES="$(IFS=','; echo "${_parts[*]}")"
fi

if [[ "$RESOLVER" == "custom" && -z "$SERVER_NAMES" ]]; then
  if [[ $INTERACTIVE -eq 1 ]]; then
    SERVER_NAMES="$(ask_text "dnscrypt-proxy server names, comma separated (see public-resolvers.md)" "")"
  fi
  [[ -n "$SERVER_NAMES" ]] || die "--resolver custom needs --server-names"
fi

if [[ "$TRANSPORT" == "obfs4" ]]; then
  [[ -n "$OBFS4_FILE" && -f "$OBFS4_FILE" ]] || die "--transport obfs4 needs --obfs4-bridges-file (see config/bridges/obfs4.conf.example)"
  grep -q '^Bridge obfs4 ' "$OBFS4_FILE" || die "no 'Bridge obfs4' lines in $OBFS4_FILE"
fi

if [[ "$LISTEN_IP" != "127.0.0.1" ]]; then
  echo "WARNING: DNS will be published on $LISTEN_IP:53. Make sure your firewall allows only your own network," >&2
  echo "         otherwise you are running an open resolver." >&2
fi

# ---------------------------------------------------------------- resolver names
case "$RESOLVER" in
  quad9) NAMES="'quad9-dnscrypt-ip4-filter-pri', 'quad9-doh-ip4-port443-filter-pri'" ;;
  adguard) NAMES="'adguard-dns-doh'" ;;
  cloudflare) NAMES="'cloudflare'" ;;
  custom)
    NAMES=""
    IFS=',' read -r -a _sn <<<"${SERVER_NAMES// /}"
    for n in "${_sn[@]}"; do
      [[ "$n" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid server name: $n"
      NAMES+="${NAMES:+, }'$n'"
    done ;;
esac

# ---------------------------------------------------------------- file writers
write_file() { # write_file <path> (content on stdin)
  local path="$1"
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '\n######## %s ########\n' "$path"
    cat
  else
    mkdir -p "$(dirname "$path")"
    cat >"$path"
  fi
}

gen_torrc() {
  cat <<EOF
# Generated by tor-dns-shield ${VERSION}
DataDirectory /var/lib/tor
Log notice stdout
SocksPort 0.0.0.0:9050
SocksPolicy accept ${SUBNET}
SocksPolicy reject *
ClientOnly 1
AvoidDiskWrites 1
EOF
  if [[ -n "$EXCLUDE_NODES" ]]; then
    cat <<EOF

# Never use exit nodes in these countries (GeoIP database of Tor; may differ from other GeoIP sources)
ExcludeExitNodes ${EXCLUDE_NODES}
GeoIPExcludeUnknown 1
StrictNodes 1
EOF
  fi
  case "$TRANSPORT" in
    snowflake)
      printf '\nUseBridges 1\nClientTransportPlugin snowflake exec /usr/bin/snowflake-client\n'
      grep -v '^#' "$SCRIPT_DIR/config/bridges/snowflake.conf" | grep -v '^$' ;;
    obfs4)
      printf '\nUseBridges 1\nClientTransportPlugin obfs4 exec /usr/bin/lyrebird\n'
      grep '^Bridge obfs4 ' "$OBFS4_FILE" ;;
    direct) : ;;
  esac
}

gen_dnscrypt() {
  cat <<EOF
# Generated by tor-dns-shield ${VERSION}
server_names = [${NAMES}]
listen_addresses = ['0.0.0.0:5353']
max_clients = 250

# Everything goes through Tor. Tor carries TCP only.
proxy = 'socks5://${IP_TOR}:9050'
force_tcp = true
netprobe_address = '${IP_TOR}:9050'
netprobe_timeout = 180

ipv6_servers = false
dnscrypt_servers = true
doh_servers = true
require_dnssec = true
require_nolog = true
require_nofilter = false

cache = true
cache_size = 4096
timeout = 15000
keepalive = 30
log_level = 2

# The resolver list itself is fetched directly (not through Tor) using this bootstrap resolver.
bootstrap_resolvers = ['9.9.9.11:53']
ignore_system_dns = true

[sources.public-resolvers]
urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md', 'https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md']
cache_file = '/var/cache/dnscrypt-proxy/public-resolvers.md'
# Key published by the dnscrypt-proxy project; verify against upstream if in doubt.
minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
refresh_delay = 72
prefix = ''
EOF
}

gen_compose() {
  cat <<EOF
# Generated by tor-dns-shield ${VERSION}
name: tor-dns-shield
networks:
  tds:
    driver: bridge
    ipam:
      config:
        - subnet: ${SUBNET}

services:
  tor:
    build: ./tor
    container_name: tds-tor
    restart: unless-stopped
    volumes:
      - ./tor/torrc:/etc/tor/torrc:ro
      - tor-data:/var/lib/tor
    networks:
      tds:
        ipv4_address: ${IP_TOR}
    cap_drop: [ALL]
    security_opt: [no-new-privileges:true]
    # No ports published: SOCKS is reachable only inside the Docker network.

  dnscrypt:
    build: ./dnscrypt
    container_name: tds-dnscrypt
    restart: unless-stopped
    depends_on: [tor]
    volumes:
      - ./dnscrypt/dnscrypt-proxy.toml:/etc/dnscrypt-proxy/dnscrypt-proxy.toml:ro
      - dnscrypt-cache:/var/cache/dnscrypt-proxy
    networks:
      tds:
        ipv4_address: ${IP_DNSCRYPT}
    cap_drop: [ALL]
    security_opt: [no-new-privileges:true]
EOF
  if [[ "$USE_ADGUARD" != "yes" ]]; then
    cat <<EOF
    ports:
      - "${LISTEN_IP}:53:5353/udp"
      - "${LISTEN_IP}:53:5353/tcp"
EOF
  else
    cat <<EOF

  adguard:
    image: adguard/adguardhome:latest
    container_name: tds-adguard
    restart: unless-stopped
    depends_on: [dnscrypt]
    volumes:
      - adguard-work:/opt/adguardhome/work
      - adguard-conf:/opt/adguardhome/conf
    networks:
      tds:
        ipv4_address: ${IP_ADGUARD}
    ports:
      - "${LISTEN_IP}:53:53/udp"
      - "${LISTEN_IP}:53:53/tcp"
      - "127.0.0.1:3000:3000/tcp"   # admin UI: localhost only. Use an SSH tunnel to reach it remotely.
    security_opt: [no-new-privileges:true]
EOF
  fi
  if [[ "$SNOWFLAKE_PROXY" == "yes" ]]; then
    cat <<EOF

  # Optional volunteer proxy: helps people in countries that block Tor.
  # Separate from the chain above; your own traffic does not use it.
  snowflake-proxy:
    image: thetorproject/snowflake-proxy:latest
    container_name: tds-snowflake-proxy
    network_mode: host      # as recommended by the Tor Project (WebRTC NAT traversal)
    restart: unless-stopped
    command: ["-capacity", "${SNOWFLAKE_CAPACITY}"]
    security_opt: [no-new-privileges:true]
EOF
  fi
  cat <<EOF

volumes:
  tor-data:
  dnscrypt-cache:
EOF
  if [[ "$USE_ADGUARD" == "yes" ]]; then printf '  adguard-work:\n  adguard-conf:\n'; fi
}

# ---------------------------------------------------------------- run
info "tor-dns-shield ${VERSION}"
info "excluded exit countries : ${EXCLUDE_NODES:-none}"
info "resolver / transport    : ${RESOLVER} / ${TRANSPORT}"
info "AdGuard Home            : ${USE_ADGUARD}"
info "volunteer Snowflake     : ${SNOWFLAKE_PROXY}"

if [[ $DRY_RUN -eq 0 ]]; then
  [[ $EUID -eq 0 ]] || die "run as root (sudo ./install.sh)"
  command -v docker >/dev/null 2>&1 || die "Docker is required: https://docs.docker.com/engine/install/"
  docker compose version >/dev/null 2>&1 || die "Docker Compose v2 plugin is required"
  if [[ $INTERACTIVE -eq 1 && "$(ask_yesno "Install into ${INSTALL_DIR}?" yes)" != "yes" ]]; then die "aborted"; fi
  mkdir -p "$INSTALL_DIR"
  cp -r "$SCRIPT_DIR/docker/tor" "$INSTALL_DIR/tor"
  cp -r "$SCRIPT_DIR/docker/dnscrypt" "$INSTALL_DIR/dnscrypt"
  mkdir -p "$INSTALL_DIR/scripts"
  cp "$SCRIPT_DIR/scripts/selftest.sh" "$INSTALL_DIR/scripts/selftest.sh"
  chmod +x "$INSTALL_DIR/scripts/selftest.sh"
fi

gen_torrc     | write_file "$INSTALL_DIR/tor/torrc"
gen_dnscrypt  | write_file "$INSTALL_DIR/dnscrypt/dnscrypt-proxy.toml"
gen_compose   | write_file "$INSTALL_DIR/docker-compose.yml"

if [[ $DRY_RUN -eq 1 ]]; then
  info "dry-run: nothing was written or started."
  exit 0
fi

# torrc must be readable by the unprivileged tor user inside the container
chmod 644 "$INSTALL_DIR/tor/torrc" "$INSTALL_DIR/dnscrypt/dnscrypt-proxy.toml"

info "building and starting containers (first build takes a few minutes)"
(cd "$INSTALL_DIR" && docker compose up -d --build)

info "waiting for Tor to bootstrap (up to 3 minutes)"
for _ in $(seq 1 36); do
  if docker logs tds-tor 2>&1 | grep -q 'Bootstrapped 100%'; then break; fi
  sleep 5
done

cp "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/uninstall.sh"
chmod +x "$INSTALL_DIR/uninstall.sh"

info "running self-test"
"$INSTALL_DIR/scripts/selftest.sh" || echo "Self-test reported problems: see messages above and 'docker logs tds-tor'."

cat <<EOF

Done. DNS is published on ${LISTEN_IP}:53.
EOF
if [[ "$USE_ADGUARD" == "yes" ]]; then
  cat <<EOF

AdGuard Home first-run setup:
  1. Open http://127.0.0.1:3000 (from a remote server: ssh -L 3000:127.0.0.1:3000 user@server).
  2. In the wizard keep the DNS listener on port 53 and the admin UI on port 3000.
  3. In Settings > DNS settings set the upstream DNS server to:  ${IP_DNSCRYPT}:5353
  4. Untick nothing else; leave "Parallel requests" off (a single upstream).
EOF
fi
cat <<EOF

Point your devices or router at ${LISTEN_IP} only if that address is reachable from them.
Uninstall: sudo ${INSTALL_DIR}/uninstall.sh   (copied there for convenience)
EOF
