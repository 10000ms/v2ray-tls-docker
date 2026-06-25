# Build a custom Caddy v2 binary with optional extra modules.
# This is only needed when you want plugins that aren't in the official image,
# e.g. a DNS provider for the ACME DNS-01 challenge (useful when port 80 is
# blocked or you want wildcard certs).
#
# Pass modules via the CADDY_MODULES build arg, comma-separated, using Caddy v2
# module paths, e.g.:
#   CADDY_MODULES=github.com/caddy-dns/cloudflare
# genconf.sh writes this into a .env file from its -p option.
ARG CADDY_VERSION=2
FROM caddy:${CADDY_VERSION}-builder AS builder

ARG CADDY_MODULES=""
RUN set -eux; \
    args=""; \
    for m in $(echo "$CADDY_MODULES" | tr ',' ' '); do \
      args="$args --with $m"; \
    done; \
    xcaddy build $args

FROM caddy:${CADDY_VERSION}-alpine
LABEL maintainer="Sparkness"
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
