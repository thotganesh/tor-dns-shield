# dnscrypt-proxy from the Debian archive (no third-party images).
FROM debian:trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends dnscrypt-proxy ca-certificates bind9-dnsutils \
 && mkdir -p /var/cache/dnscrypt-proxy \
 && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/usr/sbin/dnscrypt-proxy", "-config", "/etc/dnscrypt-proxy/dnscrypt-proxy.toml"]
