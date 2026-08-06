#!/bin/bash
set -eu

RED="31m"
GREEN="32m"
YELLOW="33m"
BLUE="36m"

usage="$(basename "$0") [-h] [-m -d -p -f]\n\n
      Please use the following options:\n\n
      -h help\n\n
      -m your email address eg: user@admin.com\n\n
      -d your dns eg: www.example.com\n\n
      -p (optional) extra Caddy v2 modules, comma-separated Go module paths\n
         eg: github.com/caddy-dns/cloudflare\n\n
      -f (optional) overwrite an existing config/ directory\n
         WARNING: this mints a new UUID and WebSocket path, which invalidates\n
         every client already configured against this server.\n"

colorEcho(){
  COLOR=$1
  echo -e "\033[${COLOR}${@:2}\033[0m"
}

EMAIL=""
V2RAY_DOMAIN=""
PLUGINS=""
FORCE=""

# NOTE: -h takes no argument, so it must NOT be followed by ':' here.
while getopts ":hm:d:p:f" opt; do
  case $opt in
    h)
      echo -e $usage
      exit
      ;;
    m)
      EMAIL=$OPTARG
      ;;
    d)
      V2RAY_DOMAIN=$OPTARG
      ;;
    p)
      PLUGINS=$OPTARG
      ;;
    f)
      FORCE=1
      ;;
    \?)
      colorEcho ${RED}"Invalid option: -$OPTARG"
      echo -e $usage
      exit 1
      ;;
  esac
done

if [[ -z $EMAIL ]]; then
  colorEcho ${YELLOW} "Please set your email address."
  echo -e ${usage}
  exit 1
fi

if [[ -z $V2RAY_DOMAIN ]]; then
  colorEcho ${YELLOW} "Please set your domain."
  echo -e ${usage}
  exit 1
fi

# Regenerating mints a fresh UUID + WebSocket path. Doing that by accident
# silently breaks every client that is already pointed at this server, so it
# has to be asked for explicitly.
if [[ -e config/config.json && -z $FORCE ]]; then
  colorEcho ${YELLOW} "config/config.json already exists."
  colorEcho ${YELLOW} "Re-running would mint a new UUID and path and break existing clients."
  colorEcho ${YELLOW} "Pass -f if that is what you want, or delete config/ first."
  exit 1
fi

genUuid(){
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  elif command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import uuid; print(uuid.uuid4())'
  else
    colorEcho ${RED} "No way to generate a UUID (need /proc, uuidgen or python3)."
    exit 1
  fi
}

PORT=$(( RANDOM + 10000 ))
# NOTE: do NOT name these PATH — that overrides the shell's $PATH.
WS_PATH=$(genUuid)
UUID=$(genUuid)

mkdir -p config

sed "s/{PORT}/$PORT/g; s/{UUID}/$UUID/g; s/{PATH}/$WS_PATH/g" files/v2ray-server.template > config/config.json
sed "s/{URI}/$V2RAY_DOMAIN/g; s/{PATH}/$WS_PATH/g; s/{UUID}/$UUID/g" files/v2ray-client.template > config/client.json
sed "s/{URI}/$V2RAY_DOMAIN/g; s/{PATH}/$WS_PATH/g; s/{UUID}/$UUID/g" files/mihomo-client.template > config/client-mihomo.yaml
sed "s/{URI}/$V2RAY_DOMAIN/g; s/{EMAIL}/$EMAIL/g; s/{PATH}/$WS_PATH/g; s/{PORT}/$PORT/g" files/caddyfile.template > config/Caddyfile

# Share link (VLESS URL scheme). Imports into v2rayN / v2rayNG / Nekoray /
# Shadowrocket / mihomo GUIs in one paste. '/' in the path must be %2F-escaped;
# every other value here is a UUID or a hostname, which need no escaping.
echo "vless://${UUID}@${V2RAY_DOMAIN}:443?encryption=none&security=tls&sni=${V2RAY_DOMAIN}&type=ws&host=${V2RAY_DOMAIN}&path=%2F${WS_PATH}#${V2RAY_DOMAIN}" > config/share-link.txt

# Extra Caddy modules for the (optional) custom build. docker-compose.build.yaml
# reads CADDY_MODULES from this .env file as a build arg.
echo "CADDY_MODULES=${PLUGINS}" > .env

colorEcho ${GREEN} "Wrote config/ — server: config.json + Caddyfile"
colorEcho ${GREEN} "Client, pick whichever your app wants:"
colorEcho ${BLUE}  "  $(pwd)/config/share-link.txt     vless:// link (v2rayN, NekoRay, Shadowrocket, ...)"
colorEcho ${BLUE}  "  $(pwd)/config/client.json        Xray-core / v2ray-core config"
colorEcho ${BLUE}  "  $(pwd)/config/client-mihomo.yaml mihomo (Clash.Meta) proxies: entry"
