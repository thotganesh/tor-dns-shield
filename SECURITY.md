# Security policy

Report vulnerabilities privately through GitHub "Report a vulnerability" (Security tab), not through public issues.

Scope: `install.sh`, `uninstall.sh`, `scripts/`, the Dockerfiles and generated configuration. Issues in Tor, dnscrypt-proxy, AdGuard Home or the Snowflake proxy belong to their own projects.

Design principles: nothing is piped from the network into a shell; no service publishes ports beyond `127.0.0.1` unless the operator explicitly chooses another `--listen-ip`; Tor SOCKS stays inside the Docker network.
