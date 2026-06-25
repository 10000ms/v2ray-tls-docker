#!/bin/bash
RED="31m"
GREEN="32m"
YELLOW="33m"
BLUE="36m"

usage="$(basename "$0") [-h] [-m -d -p]\n\n
      Please use the following options:\n\n
      -h help\n\n
      -m your email address eg: user@admin.com\n\n
      -d your dns eg: www.example.com\n\n
      -p (optional) extra Caddy v2 modules, comma-separated Go module paths\n
         eg: github.com/caddy-dns/cloudflare\n"

colorEcho(){
  COLOR=$1
  echo -e "\033[${COLOR}${@:2}\033[0m"
}

while getopts ":h:m:d:p:" opt; do
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
    \?)
      colorEcho ${RED}"Invalid option: -$opt"
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

let PORT=$RANDOM+10000
# NOTE: do NOT name these PATH — that overrides the shell's $PATH.
WS_PATH=$(cat /proc/sys/kernel/random/uuid)
UUID=$(cat /proc/sys/kernel/random/uuid)

mkdir -p config

sed "s/{PORT}/$PORT/; s/{UUID}/$UUID/; s/{PATH}/$WS_PATH/" files/v2ray-server.template > config/config.json
sed "s/{URI}/$V2RAY_DOMAIN/; s/{PATH}/$WS_PATH/; s/{UUID}/$UUID/" files/v2ray-client.template > config/client.json
sed "s/{URI}/$V2RAY_DOMAIN/; s/{EMAIL}/$EMAIL/; s/{PATH}/$WS_PATH/; s/{PORT}/$PORT/" files/caddyfile.template > config/Caddyfile

# Extra Caddy modules for the (optional) custom build. docker-compose.build.yaml
# reads CADDY_MODULES from this .env file as a build arg.
echo "CADDY_MODULES=${PLUGINS}" > .env

colorEcho ${GREEN} "Please use $(pwd)/config/client.json to configure your client."
