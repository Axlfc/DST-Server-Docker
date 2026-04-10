#!/usr/bin/env bash
set -e

DST_DIR=${DST_DIR:-/opt/dst_server}
DATA_DIR=${DATA_DIR:-/data}
SKIP_UPDATE=${SKIP_UPDATE:-false}
APP_ID=343050

# find steamcmd
STEAMCMD=""
if command -v steamcmd >/dev/null 2>&1; then
  STEAMCMD=$(command -v steamcmd)
elif [ -x "/steamcmd/steamcmd.sh" ]; then
  STEAMCMD="/steamcmd/steamcmd.sh"
elif [ -x "/home/steam/steamcmd/steamcmd.sh" ]; then
  STEAMCMD="/home/steam/steamcmd/steamcmd.sh"
elif [ -x "/home/steam/steamcmd" ]; then
  STEAMCMD="/home/steam/steamcmd"
fi

if [ -z "$STEAMCMD" ]; then
  echo "ERROR: steamcmd not found in image."
  exit 1
fi

mkdir -p "$DST_DIR" "$DATA_DIR"
chown -R "$(id -u):$(id -g)" "$DST_DIR" "$DATA_DIR" || true

if [ "$SKIP_UPDATE" != "true" ]; then
  echo "Updating app ${APP_ID} to ${DST_DIR}..."
  "$STEAMCMD" +@ShutdownOnFailedCommand 1 +login anonymous +force_install_dir "$DST_DIR" +app_update ${APP_ID} validate +quit || {
    echo "SteamCMD app_update failed (non-zero exit). Continuing to attempt to start server."
  }
else
  echo "SKIP_UPDATE=true, skipping SteamCMD update."
fi

echo "Searching server binary in ${DST_DIR}..."
SERVER_BIN=$(find "$DST_DIR" -type f -executable -iname "*dontstarve*dedicated*server*nullrenderer*" -print -quit || true)
if [ -z "$SERVER_BIN" ]; then
  SERVER_BIN=$(find "$DST_DIR" -type f -executable -iname "*dontstarve*dedicated*server*" -print -quit || true)
fi
if [ -z "$SERVER_BIN" ]; then
  SERVER_BIN=$(find "$DST_DIR" -type f -executable -iname "*server*" -print -quit || true)
fi

if [ -z "$SERVER_BIN" ]; then
  echo "No server binary found in $DST_DIR. Listing tree for debugging:"
  ls -la "$DST_DIR"
  exec "$SHELL"
fi

echo "Starting server: $SERVER_BIN"
ARGS="-console -persistent_storage_root ${DATA_DIR} -cluster ${CLUSTER_DIR:-Cluster_1} -shard ${SHARD_NAME:-Master}"
if [ "$#" -gt 0 ]; then
  ARGS="$ARGS $*"
fi

exec "$SERVER_BIN" $ARGS
