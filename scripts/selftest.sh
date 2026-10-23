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

if command -v ss >/dev/null 2>&1; then
  if ss -Hlntu 2>/dev/null | awk "{print \$5}" | grep -Eq "^(0\.0\.0\.0|\*|\[::\]):53$"; then
    warn "port 53 is listening on all interfaces: you may be running an open resolver"
  else
    ok "port 53 is not listening on all interfaces"
  fi
fi
warn "exit-country exclusion is enforced by Tor GeoIP; it is not verified by this test"
exit $fail
