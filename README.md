# tor-dns-shield

> **Status: v0.1.1.** The full chain (Tor bootstrap over Snowflake, DNS through Tor, AdGuard first run) has been verified end-to-end on a real Ubuntu host. This was exercised on a single machine/network so far — please still report problems in Issues, especially on different distros or network setups (corporate NAT, IPv6-only, etc.).

**Private DNS over Tor (Snowflake / obfs4 / direct), with per-country exit exclusion, optional AdGuard Home, and an optional volunteer Snowflake proxy.**

One interactive script. You choose the countries whose exit nodes you want to avoid, the upstream resolver and the transport; it generates a `docker-compose.yml` and starts everything.

[Italiano](docs/README.it.md) · [Français](docs/README.fr.md)

```
devices ──> [AdGuard Home] ──> dnscrypt-proxy ──> Tor (Snowflake bridge) ──> Quad9 / other resolver
              optional          DoH/DNSCrypt        exit country excluded
```

## What it protects, and what it does not

| Protects | Does **not** protect |
|---|---|
| Your resolver never sees your IP (it sees a Tor exit) | Your ISP still sees the IP addresses you connect to |
| With Snowflake, your ISP does not see connections to known Tor relays | Browsing metadata, TLS SNI, device fingerprints |
| DNS queries are encrypted end to end (DoH/DNSCrypt) | A global adversary correlating traffic |
| Country-specific DNS blocking is harder to apply to your resolver path | Blocking by your own ISP or router at IP level |

This is **DNS privacy and resilience**, not anonymity. Please do not describe it as anonymous.

## Why this exists

Public resolvers are increasingly asked to block domains by court order. Quad9 has publicly opposed this: it won a case brought by Sony Music in Germany in 2023, and it announced that it will stop serving users in France from 24 November rather than block domains there (check the [Quad9 press page](https://quad9.net/news/press/) for the current status before relying on this). Whatever you think of those cases, the technical point stands: encrypted DNS over Tor, with exits outside a given country, is a reasonable privacy default for anyone.

The project takes no position beyond that. The installer works the same whichever country you choose.

## Install

Do not pipe this into a shell. Download, read, verify, run.

```bash
git clone https://github.com/thotganesh/tor-dns-shield && cd tor-dns-shield
sha256sum -c SHA256SUMS      # detects a corrupted checkout (see note below)
less install.sh
sudo ./install.sh
```

`SHA256SUMS` only catches corruption: an attacker who can change the scripts can change the file too. For real assurance, compare the commit hash or release tag with a copy you obtained through another channel, and read the script.

Requirements: Linux, root, Docker with the Compose v2 plugin. `whiptail` gives you menus; without it you get plain prompts.

Non-interactive example:

```bash
sudo ./install.sh --non-interactive --countries fr,it --resolver quad9 \
  --transport snowflake --adguard --snowflake-proxy
```

Preview without changing anything: add `--dry-run`.

**Re-running the installer** (e.g. after `git pull`) is safe and does not need a fresh machine: it regenerates `torrc`, `dnscrypt-proxy.toml` and `docker-compose.yml` and runs `docker compose up -d --build`. Note that Compose does not always restart a container just because a file it mounts (like `torrc`) changed — if you don't see `Recreated`/`Started` in the output, run `docker restart tds-tor` to make sure the new config is actually loaded.

### Options

| Option | Meaning |
|---|---|
| `--countries fr,it` | Exit countries to **exclude** (any ISO 3166 alpha-2). `none` disables. |
| `--resolver` | `quad9` (default), `adguard`, `cloudflare`, `custom` + `--server-names` |
| `--transport` | `snowflake` (default), `direct`, `obfs4` + `--obfs4-bridges-file` |
| `--adguard` / `--no-adguard` | AdGuard Home in front of dnscrypt-proxy |
| `--snowflake-proxy` / `--no-snowflake-proxy` | Volunteer proxy (**pre-selected**, one keypress to decline) |
| `--capacity N` | Max simultaneous users of your volunteer proxy (default 10) |
| `--listen-ip IP` | Where port 53 is published (default `127.0.0.1`) |

Each option also exists as an environment variable (`TDS_COUNTRIES`, `TDS_RESOLVER`, ...).

## Using it: point your system at the resolver

By default DNS is published on `127.0.0.1:53`. The installer does **not** touch your system's resolver configuration — you need to point it there yourself.

Check nothing else is already bound to that address/port first:
```bash
sudo ss -tulpn | grep ':53'
```

**Quick manual test (no system change needed):**
```bash
dig @127.0.0.1 example.com
```
If this returns an answer, the chain works end to end — you don't need to change your system resolver just to verify it.

**To actually use it for everything**, on a systemd-based distro (Ubuntu default):
```bash
sudo resolvectl dns <interface> 127.0.0.1
sudo resolvectl domain <interface> '~.'
```
(`<interface>` is e.g. `eth0`; find yours with `ip -br link`.) This is temporary and reverts on reboot or reconnect. For a persistent change, edit the connection in NetworkManager (DNS field) or `/etc/systemd/resolved.conf` (`DNS=127.0.0.1`, `DNSStubListener=no`), then `sudo systemctl restart systemd-resolved`.

Verify it is really being used, not bypassed:
```bash
resolvectl status          # should show 127.0.0.1 as the active DNS server
dig example.com            # no @server specified: should still resolve via the chain
```

## Snowflake: two different things

1. **Snowflake client** (inside the `tor` container). Used by *you* to reach Tor without your ISP seeing connections to Tor relays. Slower to start than plain Tor. Not needed if Tor is not blocked and you do not mind your ISP knowing you use Tor.
2. **Snowflake proxy** (separate container, optional). Used by *other people* in countries that block Tor. It is not your entry point and does not improve your own privacy. Declining it changes nothing for you.

### The volunteer proxy: what it does, sees, costs

- Relays encrypted traffic between censored users and Tor. You are **not an exit node**; you cannot read the traffic.
- Your public IP address is visible to the users who connect through you.
- Uses bandwidth, roughly in proportion to `--capacity`. Check your hosting provider's terms and any traffic quota.
- Behind a restrictive NAT it helps fewer people.
- It is pre-selected because it helps the network. The prompt states all of the above and declining costs one keypress.

## Security notes

- Port 53 is published on `127.0.0.1` by default. If you set `--listen-ip` to a LAN or public address, restrict it with a firewall or you run an open resolver.
- The AdGuard admin UI is bound to `127.0.0.1:3000`. Reach it through an SSH tunnel.
- Tor SOCKS is bound to `0.0.0.0:9050` inside the `tor` container but never published to the host; `SocksPolicy` additionally restricts it to the Docker subnet and to `127.0.0.1` (the latter so in-container checks, e.g. `scripts/selftest.sh`, are not silently dropped). It is not reachable from outside this host either way.
- Country exclusion uses Tor's GeoIP database, which may disagree with other databases. `StrictNodes 1` means a failure to build a circuit breaks DNS instead of falling back. This is deliberate. Note: with Snowflake/obfs4, `GeoIPExcludeUnknown` is intentionally **not** set, because pluggable-transport bridges use a placeholder address with no GeoIP country and would otherwise be discarded outright (see CHANGELOG, v0.1.1).
- The resolver list (`public-resolvers.md`) is verified with minisign. To resolve the list's hostnames at first start, dnscrypt-proxy uses the bootstrap resolver `9.9.9.11` directly (not through Tor), so Quad9 can see that one lookup from your IP.
- Images for Tor and dnscrypt-proxy are built from `debian:trixie-slim` using Debian packages (including `tor-geoipdb`, which country exclusion needs). AdGuard Home and the Snowflake proxy use the official images (`adguard/adguardhome`, `thetorproject/snowflake-proxy`); pin them by digest if you need reproducibility.

## Known limits / roadmap

- Single Tor instance. Failover between two instances is not implemented yet.
- The Docker subnet `172.28.0.0/24` is fixed; if it clashes with a network you use, edit `SUBNET`/`IP_*` at the top of `install.sh`.
- Verified so far on one Ubuntu VM / one network path (including over NAT'd/mobile tethering, where Snowflake's WebRTC rendezvous is slower but still completes). Different distros, routers or restrictive corporate networks may surface new issues — please report them.
- AdGuard Home needs its first-run wizard in the browser; the installer prints the exact upstream to set.
- Snowflake bridge parameters change; refresh `config/bridges/snowflake.conf` from Tor Browser if it stops connecting.
- No automatic verification of the exit country yet.
- Resolver names (`quad9-...`, `adguard-dns-doh`, `cloudflare`) must exist in the public resolver list; use `--resolver custom` if upstream renames them.

## Tests

`python3 tests/test_generator.py` (needs `pyyaml`) runs the generator over 100+ option combinations and checks the generated files: port exposure, optional services, country exclusion, input validation.

## Legal

You are responsible for complying with the laws of your country and the terms of your hosting provider. Using Tor and running a Snowflake proxy are legal in most countries, but check yours. Provided as is, MIT license.
