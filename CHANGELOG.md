# Changelog

## v0.1.1

### Fixed
- **Snowflake/obfs4 bridges were silently discarded whenever an exit-country exclusion was set.** `GeoIPExcludeUnknown 1` combined with `StrictNodes 1` rejected pluggable-transport bridges, because their bridge line uses a placeholder address (e.g. `192.0.2.3`, per Tor's own documented convention — the real endpoint is negotiated by the transport itself, e.g. Snowflake's broker) with no country in any GeoIP database. Tor's log showed a continuous `Not using bridge at [scrubbed]: it is in ExcludeNodes` loop and never bootstrapped. `GeoIPExcludeUnknown` is now only set in `--transport direct` mode, where every node really is a normal relay with a known GeoIP country.
- **`SocksPolicy` rejected connections from `127.0.0.1`**, accepting only the Docker subnet (`172.28.0.0/24`). Tor itself worked correctly, but any check run from inside the `tor` container against `127.0.0.1:9050` (including `scripts/selftest.sh`) was silently dropped (`Denying socks connection from untrusted address 127.0.0.1`), reporting a false "Tor check failed" even on a fully bootstrapped, working setup. `SocksPolicy accept 127.0.0.1/32` was added; it is not reachable from outside the host.

### Notes
- Both issues only reproduce when an exit-country exclusion is active (first issue) or when testing from inside the `tor` container at loopback (second issue) — a plain `--transport direct` install without `--countries` would not have shown either.
