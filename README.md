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
  git clone https://github.com/10000ms/v2ray-tls-docker.git
  cd v2ray-tls-docker
  # {email} is your email (for Let's Encrypt), {dns} is your server's domain
  ./genconf.sh -m {email} -d {dns}
  docker compose up -d
  ```

  `genconf.sh` generates, into `config/`:

  | File | What it is |
  |---|---|
  | `config.json` | V2Ray **server** config (mounted into the v2ray container) |
  | `Caddyfile` | Caddy v2 config (mounted into the web-server container) |
  | `share-link.txt` | `vless://` share link — paste into v2rayN / v2rayNG / NekoRay / Shadowrocket |
  | `client.json` | **Client** config for Xray-core / v2ray-core |
  | `client-mihomo.yaml` | `proxies:` entry for mihomo (Clash.Meta) |

  Every generated file carries the same UUID, WebSocket path and domain, so any one of
  them will connect to the server the same way — pick whichever your client app wants.

  Caddy obtains and renews the TLS certificate automatically on first start; certs are
  persisted in the `caddy_data` Docker volume, so restarts don't re-hit Let's Encrypt.

  Re-running `genconf.sh` mints a **new** UUID and path, which invalidates every client
  already configured against the server. It therefore refuses to overwrite an existing
  `config/` unless you pass `-f`.

## Upgrading an old deployment (VMess / `alterId`)

If your server was deployed from this repo before 2019 it is running **VMess with
`alterId`** on a v2ray core of that era, and modern clients cannot connect to it.
Three independent things have broken:

1. **Xray-core deleted the legacy half.** `alterId > 0` selects VMess's original
   MD5-based authentication. Xray-core removed that code
   ([PR #2199](https://github.com/XTLS/Xray-core/pull/2199), merged June 2023), so a
   current Xray client has no code path that can authenticate against an `alterId`
   server. mihomo does still carry a legacy path — its docs describe `alterId` as
   "if not `0`, the legacy protocol is enabled" — but it only works when the client's
   `alterId` matches the server's. Set either side to `0` and the two ends are running
   different algorithms.
2. **Setting `alterId: 0` on the old core does not rescue it.** `alterId: 0` means
   "VMessAEAD only", and VMessAEAD only arrived in v2ray-core **v4.28.0** (late 2020) —
   long after that image was built. AEAD and the legacy MD5 scheme are different
   algorithms, so an old binary told to serve `alterId: 0` still cannot answer a
   modern client. That is the squeeze: the old core can only speak legacy, current
   Xray can only speak AEAD. **The core itself has to be replaced** — no config edit
   fixes this.
3. **Check the certificate as well.** The old `web-server` image is a 2018 build of
   Caddy (v0.x/v1) that nothing has updated since, and ACME has moved on — Let's
   Encrypt disabled the ACMEv1 protocol entirely in 2021. Stale ACME clients are a
   common cause of silent renewal failure. `curl -vI https://{dns}` will show whether
   the certificate is still valid; if it has expired, that alone blocks every client
   regardless of protocol.

Current `master` already replaces all of it: **VLESS over WebSocket + TLS** on
`v2fly/v2fly-core` behind **Caddy v2**. VLESS has no `alterId` and no legacy MD5
mode, so this entire class of breakage is gone.

### Redeploy

Run on the server, in the old checkout's directory:

```bash
# 0. See what you're actually running, so you know what you're replacing.
docker ps
grep -E '"protocol"|alterId' config/config.json

# 1. Stop the old stack — it holds ports 80/443 and the new one needs them.
docker compose down            # older installs: docker-compose down

# 2. Get the current code. Back the old config out of the way first:
#    it holds your previous UUID, and genconf.sh will not overwrite it.
mv config config.old
git pull

# 3. Regenerate. Same domain as before is fine.
./genconf.sh -m {email} -d {dns}

# 4. Pull current images and start.
docker compose pull
docker compose up -d
docker compose logs -f         # Ctrl-C once Caddy reports a certificate
```

`docker-compose.yaml` follows the Compose Spec and carries no `version:` key, which
needs **Compose v2** (`docker compose`) or at least docker-compose 1.27. A 2018-era
server may well have something older that rejects the file — upgrade Docker Compose
rather than adding a `version:` line back.

The new server has a **new UUID and a new WebSocket path**, so every client has to be
reconfigured from the freshly generated `config/` files — the old client entry will
never work again. Delete `config.old` once the new setup is confirmed.

### Verify

```bash
# Both containers up, neither restart-looping
docker compose ps

# Which core actually got pulled
docker compose exec v2ray v2ray version

# Camouflage page + a valid, current certificate
curl -sS https://{dns}                      # -> Hello, world!
curl -sSI https://{dns} 2>&1 | head -1      # -> HTTP/2 200

# The WebSocket path. A plain GET is not an upgrade request, so V2Ray rejects it.
curl -sS -o /dev/null -w '%{http_code}\n' "https://{dns}/$(sed -n 's|.*"path": "/\(.*\)".*|\1|p' config/config.json)"
```

Read the last one by its status code — the three outcomes mean different things:

| Code | Meaning |
|---|---|
| **400** | Correct. Caddy routed to V2Ray and V2Ray refused a non-WebSocket request. |
| **502** | Caddy matched the route but cannot reach the `v2ray` container — check that the container is up and that the port in `Caddyfile` matches `config.json`. |
| **200** `Hello, world!` | The route did **not** match; the request fell through to the camouflage handler. The path in `Caddyfile` and `config.json` disagree. |

If the certificate step fails, the usual cause is port 80 being unreachable (firewall,
security group, or something else still bound to it). If the domain is behind
Cloudflare's proxy, set SSL/TLS mode to **Full (strict)**.

## Client setup

  * **v2rayN / v2rayNG / NekoRay / Shadowrocket** — import `config/share-link.txt`.
  * **Xray-core / v2ray-core CLI** — use `config/client.json`. It exposes SOCKS5 on
    `127.0.0.1:10808` and HTTP on `127.0.0.1:10809`. Both are bound to loopback; if you
    want to serve other machines on your LAN, change `listen` to `0.0.0.0` yourself and
    firewall the ports — an open proxy on `0.0.0.0` is a real risk, so it is not the default.
  * **mihomo (Clash.Meta)** — merge the item in `config/client-mihomo.yaml` into your
    own config's `proxies:` list and reference it from a `proxy-groups:` entry.

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

### Running Xray-core instead of v2fly

  The generated `config.json` is plain v4-format JSON, which
  [Xray-core](https://github.com/XTLS/Xray-core) also reads. To swap cores, change the
  `v2ray` service in `docker-compose.yaml` to:

  ```yaml
    v2ray:
      image: ghcr.io/xtls/xray-core:latest
      restart: always
      command: ["run", "-c", "/etc/xray/config.json"]
      volumes:
        - ./config/config.json:/etc/xray/config.json:ro
  ```

  Nothing else changes — the Caddyfile still reverse-proxies to `v2ray:{PORT}`, and
  clients are unaffected. Both cores have been run against the same generated
  `config.json` end to end; v2ray-core and mihomo clients connect to either one.

  Two things worth knowing before you pick:

  * `v2fly/v2fly-core:latest` **lags upstream**. Its publishing workflow is triggered
    by hand rather than by each release, so the tag can sit months behind the newest
    v2ray-core. Check what you actually got with `docker compose exec v2ray v2ray version`.
    Any 5.x is fine for this stack — VLESS support is long-standing — but do not assume
    `latest` means current.
  * Xray-core now prints `The feature WebSocket transport ... is deprecated ... Please
    migrate to XHTTP H2 & H3` on startup. WebSocket still works, and it remains the
    transport of choice behind a CDN, but the warning is a signal about where Xray is
    heading.
