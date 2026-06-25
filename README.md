# v2ray-tls-docker

## Intro
[V2Ray](https://www.v2fly.org/ "Project V") is a platform for building proxies to bypass network restrictions. Its transport supports WebSocket, so we can put a web server such as [Caddy](https://caddyserver.com/) in front of it and enable TLS for a more secure, less detectable channel. Setting this up by hand is tedious — especially config files and TLS certificates — so it's packaged as Docker containers to simplify deployment and maintenance. You can also put a CDN (e.g. Cloudflare) in front for DNS + HTTP proxying.

This stack uses **VLESS over WebSocket + TLS**, fronted by **Caddy v2** (automatic HTTPS via Let's Encrypt). It runs the official `v2fly/v2fly-core` and `caddy:2` images — no custom build required.

## Prerequisites
  * A Linux server with a public IP (any arch — the images are multi-arch)
  * A domain name whose A/AAAA record points at the server
  * Docker + Docker Compose
  * Ports **80** and **443** reachable from the internet (80 is needed for ACME certificate issuance)

## Install

  ```bash
  git clone https://github.com/Sparkness/v2ray-tls-docker.git
  cd v2ray-tls-docker
  # {email} is your email (for Let's Encrypt), {dns} is your server's domain
  ./genconf.sh -m {email} -d {dns}
  # genconf.sh prints the path to config/client.json — use it to configure your client.
  docker compose up -d
  ```

  `genconf.sh` generates, into `config/`:
  * `config.json` — the V2Ray server config (mounted into the v2ray container)
  * `Caddyfile`   — the Caddy v2 config (mounted into the web-server container)
  * `client.json` — a ready-to-use **client** config (VLESS + WS + TLS)

  Caddy obtains and renews the TLS certificate automatically on first start; certs are
  persisted in the `caddy_data` Docker volume, so restarts don't re-hit Let's Encrypt.

## Customization

  The `-p` option adds extra **Caddy v2 modules** to a custom-built image — most
  commonly a DNS provider for the ACME DNS-01 challenge (handy when port 80 is
  blocked, or for wildcard certs). Pass comma-separated Go module paths:

  ```bash
  ./genconf.sh -m example@a.com -d example.com -p github.com/caddy-dns/cloudflare
  docker compose -f docker-compose.build.yaml up -d --build
  ```

  This builds Caddy with the requested modules via `xcaddy`; the v2ray container
  still uses the official image. Without `-p`, just use the default
  `docker compose up -d` above.
