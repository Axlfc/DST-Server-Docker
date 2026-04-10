#!/usr/bin/env bash
set -euo pipefail

# Directories and config
DST_DIR=${DST_DIR:-/opt/dst_server}
DATA_DIR=${DATA_DIR:-/data}
SKIP_UPDATE=${SKIP_UPDATE:-false}
APP_ID=343050

echo "Entry script: DST_DIR=$DST_DIR DATA_DIR=$DATA_DIR SKIP_UPDATE=$SKIP_UPDATE"

STEAMCMD_PATH=""

# Common locations to check for steamcmd
candidates=(
  /usr/games/steamcmd
  /usr/local/games/steamcmd
  /usr/local/bin/steamcmd
  /opt/steamcmd/steamcmd.sh
  /opt/steam/steamcmd.sh
  /steamcmd/steamcmd.sh
  /home/steam/steamcmd/steamcmd.sh
  /home/steam/steamcmd.sh
  /root/Steam/steamcmd.sh
  /root/Steam/steamcmd
)

for c in "${candidates[@]}"; do
  if [ -f "$c" ]; then
    STEAMCMD_PATH="$c"
    break
  fi
done

# Try PATH
if [ -z "$STEAMCMD_PATH" ]; then
  if command -v steamcmd >/dev/null 2>&1; then
    STEAMCMD_PATH=$(command -v steamcmd)
  fi
fi

# As a last resort, try a limited filesystem search (may be slow)
if [ -z "$STEAMCMD_PATH" ]; then
  FOUND=$(find / -maxdepth 4 -type f \( -iname 'steamcmd.sh' -o -iname 'steamcmd' \) 2>/dev/null | head -n1 || true)
  if [ -n "$FOUND" ]; then
    STEAMCMD_PATH="$FOUND"
  fi
fi

if [ -z "$STEAMCMD_PATH" ]; then
  echo "ERROR: steamcmd not found in image. Checked common locations and PATH."
  echo "You can either: (A) use an image that includes steamcmd, or (B) modify the Dockerfile to install it."
  exit 1
fi

echo "Using steamcmd at: $STEAMCMD_PATH"

mkdir -p "$DST_DIR" "$DATA_DIR"
chown -R "$(id -u):$(id -g)" "$DST_DIR" "$DATA_DIR" || true

run_steamcmd() {
  if [ -x "$STEAMCMD_PATH" ]; then
    "$STEAMCMD_PATH" "$@"
  else
    bash "$STEAMCMD_PATH" "$@"
  fi
}

if [ "$SKIP_UPDATE" != "true" ]; then
  echo "Updating app ${APP_ID} to ${DST_DIR}..."
  run_steamcmd +@ShutdownOnFailedCommand 1 +login anonymous +force_install_dir "$DST_DIR" +app_update ${APP_ID} validate +quit || {
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
  ls -la "$DST_DIR" || true
  echo "Dropping to shell for debugging."
  exec /bin/bash
fi

echo "Starting server: $SERVER_BIN"
ARGS=( -console -persistent_storage_root "${DATA_DIR}" -cluster "${CLUSTER_DIR:-Cluster_1}" -shard "${SHARD_NAME:-Master}" )
if [ "$#" -gt 0 ]; then
  ARGS+=("$@")
fi

exec "$SERVER_BIN" "${ARGS[@]}"
