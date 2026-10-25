#!/usr/bin/env bash
# Checks: Tor is working, DNS answers through the chain, DNS port exposure.
set -uo pipefail
fail=0
ok()   { echo "[ OK ] $*"; }
bad()  { echo "[FAIL] $*"; fail=1; }
warn() { echo "[WARN] $*"; }

if docker exec tds-tor curl -fsS --max-time 60 --socks5-hostname 127.0.0.1:9050 \
     https://check.torproject.org/api/ip 2>/dev/null | grep -q "\"IsTor\":true"; then
  ok "traffic leaves through the Tor network"
else
  bad "Tor check failed (see: docker logs tds-tor)"
fi

if docker exec tds-dnscrypt dig +short +time=30 +tries=1 @127.0.0.1 -p 5353 quad9.net 2>/dev/null | grep -Eq "^[0-9]"; then
  ok "dnscrypt-proxy resolves names through the chain"
else
  bad "DNS resolution failed (first start can take a few minutes; see: docker logs tds-dnscrypt)"
fi

# AdGuard Home (if installed): its upstream must be dnscrypt-proxy, otherwise DNS on port 53
# silently bypasses Tor (AdGuard's own default upstream is a direct DoH connection).
DNSCRYPT_UPSTREAM="172.28.0.11:5353"
adguard_list() { # adguard_list <yaml key>: print the "- item" values under that key
  # shellcheck disable=SC2016  # the awk program must reach awk literally
  docker exec tds-adguard awk -v key="$1" '$0 ~ "^  " key ":" {f=1; next} /^  [a-z_]+:/ {f=0} f && /^    - / {print $2}' \
    /opt/adguardhome/conf/AdGuardHome.yaml 2>/dev/null || true
}
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx tds-adguard; then
  ADG_UP="$(adguard_list upstream_dns)"
  ADG_FB="$(adguard_list fallback_dns)"
  if [ -z "$ADG_UP" ]; then
    warn "AdGuard Home has no upstream yet (first-run wizard not completed?): port 53 is NOT using this chain until you run scripts/adguard-upstream.sh"
  elif [ "$(printf '%s\n' "$ADG_UP" | sort -u)" = "$DNSCRYPT_UPSTREAM" ]; then
    ok "AdGuard Home upstream is dnscrypt-proxy (through Tor)"
  else
    bad "AdGuard Home upstream BYPASSES Tor: $(printf '%s\n' "$ADG_UP" | tr '\n' ' ') -- run scripts/adguard-upstream.sh"
  fi
  if [ -n "$ADG_FB" ]; then
    bad "AdGuard Home has fallback DNS servers that bypass Tor: $(printf '%s\n' "$ADG_FB" | tr '\n' ' ') -- run scripts/adguard-upstream.sh"
  fi
fi

if command -v ss >/dev/null 2>&1; then
  if ss -Hlntu 2>/dev/null | awk "{print \$5}" | grep -Eq "^(0\.0\.0\.0|\*|\[::\]):53$"; then
    warn "port 53 is listening on all interfaces: you may be running an open resolver"
  else
    ok "port 53 is not listening on all interfaces"
  fi
fi
warn "exit-country exclusion is enforced by Tor GeoIP; it is not verified by this test"
exit $fail
