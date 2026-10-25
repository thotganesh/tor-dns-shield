#!/usr/bin/env bash
# tor-dns-shield: force AdGuard Home to use dnscrypt-proxy (through Tor) as its ONLY upstream.
#
# Why this exists: AdGuard Home's first-run wizard leaves its own default upstream
# (DoH to Quad9, reached directly, NOT through Tor). If that upstream is not changed,
# DNS silently bypasses Tor. install.sh runs this automatically after the wizard;
# you can also re-run it by hand at any time (it is idempotent and keeps a .bak).
set -Eeuo pipefail

UPSTREAM="${TDS_UPSTREAM:-172.28.0.11:5353}"
NAME="${TDS_ADGUARD_CONTAINER:-tds-adguard}"
STOPPED=0

# If anything fails after we stopped AdGuard, bring it back up.
cleanup() {
  if [[ $STOPPED -eq 1 ]]; then docker start "$NAME" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

[[ $EUID -eq 0 ]] || { echo "ERROR: run as root (sudo $0)" >&2; exit 1; }
docker inspect "$NAME" >/dev/null 2>&1 || { echo "ERROR: container $NAME not found" >&2; exit 1; }

CONF="$(docker inspect "$NAME" --format '{{range .Mounts}}{{if eq .Destination "/opt/adguardhome/conf"}}{{.Source}}{{end}}{{end}}')"
if [[ -z "$CONF" || ! -f "$CONF/AdGuardHome.yaml" ]]; then
  echo "ERROR: AdGuardHome.yaml not found. Complete the first-run wizard at http://127.0.0.1:3000 first, then re-run." >&2
  exit 1
fi

echo "==> stopping $NAME (AdGuard rewrites its config on exit)"
docker stop "$NAME" >/dev/null
STOPPED=1

cp -p "$CONF/AdGuardHome.yaml" "$CONF/AdGuardHome.yaml.bak"
TMP="$(mktemp)"
awk -v up="$UPSTREAM" '
/^  upstream_dns:/  {print; print "    - " up; skip=1; next}
/^  bootstrap_dns:/ {print; print "    - " up; skip=1; next}
/^  fallback_dns:/  {print "  fallback_dns: []"; skip=1; next}
skip && /^    - /    {next}
{skip=0; print}
' "$CONF/AdGuardHome.yaml.bak" >"$TMP"
cat "$TMP" >"$CONF/AdGuardHome.yaml"   # cat > keeps owner and permissions
rm -f "$TMP"

echo "==> new upstream settings:"
grep -A1 -E '^  (upstream_dns|bootstrap_dns):' "$CONF/AdGuardHome.yaml" | grep -v '^--' || true
grep -E '^  fallback_dns:' "$CONF/AdGuardHome.yaml" || true

docker start "$NAME" >/dev/null
STOPPED=0
echo "==> $NAME restarted."
echo "    Verify: docker stop tds-dnscrypt; dig test\$RANDOM.example.com @127.0.0.1  (must FAIL); docker start tds-dnscrypt"
