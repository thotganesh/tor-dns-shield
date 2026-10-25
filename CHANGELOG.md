# Changelog

## v0.1.2

### Fixed
- **AdGuard Home bypassed Tor (privacy bug).** AdGuard's first-run wizard leaves its own default upstream, a direct DoH connection to Quad9 (`https://dns10.quad9.net/dns-query`, bootstrap `9.9.9.10`). The installer only *printed* a manual step telling you to point AdGuard at dnscrypt-proxy; if it was skipped, everything resolved on port 53 left the machine directly, not through Tor, while dnscrypt-proxy and Tor still looked healthy and `scripts/selftest.sh` tested dnscrypt-proxy only. It showed up as the resolver location seen in browser DNS-leak tests staying fixed instead of following the Tor exit. Earlier README text claiming the full chain was verified end-to-end was wrong for the AdGuard path.

### Added
- The installer now guides the AdGuard first run (interactive mode): it opens the wizard (best effort; prints an SSH-tunnel hint for remote servers), waits for it to finish, then sets AdGuard's upstream to dnscrypt-proxy by itself and clears any fallback DNS.
- `scripts/adguard-upstream.sh`: does that step; idempotent, keeps a `.bak`, and restarts AdGuard even if it fails midway. Also usable by hand, e.g. after `--non-interactive`.
- `scripts/selftest.sh` now fails if AdGuard's upstream is anything other than dnscrypt-proxy, or if any fallback DNS server is configured, and warns if the wizard has not been completed.

### Upgrading from v0.1.0 / v0.1.1 with AdGuard
Check what AdGuard uses: `docker exec tds-adguard grep -A2 'upstream_dns:' /opt/adguardhome/conf/AdGuardHome.yaml`. If it is not `172.28.0.11:5353`, run `git pull && sudo ./install.sh`, or `sudo /opt/tor-dns-shield/scripts/adguard-upstream.sh` after copying the script there.

## v0.1.1

### Fixed
- **Snowflake/obfs4 bridges were silently discarded whenever an exit-country exclusion was set.** `GeoIPExcludeUnknown 1` combined with `StrictNodes 1` rejected pluggable-transport bridges, because their bridge line uses a placeholder address (e.g. `192.0.2.3`, per Tor's own documented convention — the real endpoint is negotiated by the transport itself, e.g. Snowflake's broker) with no country in any GeoIP database. Tor's log showed a continuous `Not using bridge at [scrubbed]: it is in ExcludeNodes` loop and never bootstrapped. `GeoIPExcludeUnknown` is now only set in `--transport direct` mode, where every node really is a normal relay with a known GeoIP country.
- **`SocksPolicy` rejected connections from `127.0.0.1`**, accepting only the Docker subnet (`172.28.0.0/24`). Tor itself worked correctly, but any check run from inside the `tor` container against `127.0.0.1:9050` (including `scripts/selftest.sh`) was silently dropped (`Denying socks connection from untrusted address 127.0.0.1`), reporting a false "Tor check failed" even on a fully bootstrapped, working setup. `SocksPolicy accept 127.0.0.1/32` was added; it is not reachable from outside the host.

### Notes
- Both issues only reproduce when an exit-country exclusion is active (first issue) or when testing from inside the `tor` container at loopback (second issue) — a plain `--transport direct` install without `--countries` would not have shown either.
