# Tor client with Snowflake / obfs4 pluggable transports.
# tor-geoipdb is REQUIRED: without it ExcludeExitNodes cannot map relays to countries.
# Base image is pinned by tag; bump deliberately.
FROM debian:trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends tor tor-geoipdb snowflake-client obfs4proxy ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

USER debian-tor
ENTRYPOINT ["tor", "-f", "/etc/tor/torrc"]
