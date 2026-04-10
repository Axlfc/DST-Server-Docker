#!/usr/bin/env bash
set -euo pipefail

# Directories and config
DST_DIR=${DST_DIR:-/opt/dst_server}
DATA_DIR=${DATA_DIR:-/data}
CLUSTER_NAME=${CLUSTER_NAME:-DoNotStarveTogether}
CLUSTER_DIR=${CLUSTER_DIR:-Cluster_1}
SHARD_NAME=${SHARD_NAME:-Master}
SKIP_UPDATE=${SKIP_UPDATE:-false}
APP_ID=343050

echo "Entry script: DST_DIR=$DST_DIR DATA_DIR=$DATA_DIR SKIP_UPDATE=$SKIP_UPDATE"

# Handle Cluster Token from environment variable
if [ -n "${CLUSTER_TOKEN:-}" ]; then
    TOKEN_FILE="${DATA_DIR}/${CLUSTER_NAME}/${CLUSTER_DIR}/cluster_token.txt"
    echo "Writing CLUSTER_TOKEN to ${TOKEN_FILE}"
    mkdir -p "$(dirname "${TOKEN_FILE}")"
    echo "${CLUSTER_TOKEN}" > "${TOKEN_FILE}"
fi

STEAMCMD_PATH=""

# Common locations to check for steamcmd
candidates=(
  /home/steam/steamcmd/steamcmd.sh
  /usr/local/bin/steamcmd
  /opt/steamcmd/steamcmd.sh
)

for c in "${candidates[@]}"; do
  if [ -f "$c" ]; then
    STEAMCMD_PATH="$c"
    break
  fi
done

if [ -z "$STEAMCMD_PATH" ]; then
  if command -v steamcmd >/dev/null 2>&1; then
    STEAMCMD_PATH=$(command -v steamcmd)
  fi
fi

if [ -z "$STEAMCMD_PATH" ]; then
  echo "ERROR: steamcmd not found."
  exit 1
fi

echo "Using steamcmd at: $STEAMCMD_PATH"

mkdir -p "$DST_DIR" "$DATA_DIR"

run_steamcmd() {
  # SteamCMD needs to run from its own directory
  local cmd_dir
  cmd_dir=$(dirname "$(readlink -f "$STEAMCMD_PATH")")
  pushd "$cmd_dir" > /dev/null
  if [ -x "./$(basename "$STEAMCMD_PATH")" ]; then
    ./$(basename "$STEAMCMD_PATH") "$@"
  else
    bash "./$(basename "$STEAMCMD_PATH")" "$@"
  fi
  popd > /dev/null
}

if [ "$SKIP_UPDATE" != "true" ]; then
  echo "Updating app ${APP_ID} to ${DST_DIR}..."
  run_steamcmd +@ShutdownOnFailedCommand 1 +@NoPromptForPassword 1 +login anonymous +force_install_dir "$DST_DIR" +app_update ${APP_ID} validate +quit || {
    echo "SteamCMD app_update failed (non-zero exit). Continuing to attempt to start server."
  }
else
  echo "SKIP_UPDATE=true, skipping SteamCMD update."
  echo "Waiting for server binary to be available (from master container update)..."
  timeout=0
  while [ ! -f "$DST_DIR/bin/dontstarve_dedicated_server_nullrenderer" ] && [ ! -f "$DST_DIR/bin64/dontstarve_dedicated_server_nullrenderer" ] && [ $timeout -lt 600 ]; do
    sleep 10
    timeout=$((timeout + 10))
    echo "Still waiting for server binary... ($timeout/600s)"
  done
fi

echo "Searching server binary in ${DST_DIR}..."
SERVER_BIN=$(find "$DST_DIR" -type f -executable -iname "*dontstarve*dedicated*server*nullrenderer*" -print -quit || true)
if [ -z "$SERVER_BIN" ]; then
  SERVER_BIN=$(find "$DST_DIR" -type f -executable -iname "*dontstarve*dedicated*server*" -print -quit || true)
fi

if [ -z "$SERVER_BIN" ]; then
  echo "No server binary found in $DST_DIR. Listing tree for debugging:"
  ls -la "$DST_DIR" || true
  exit 1
fi

echo "Starting server: $SERVER_BIN"
ARGS=( -console -persistent_storage_root "${DATA_DIR}" -conf_dir "${CLUSTER_NAME}" -cluster "${CLUSTER_DIR}" -shard "${SHARD_NAME}" )
if [ "$#" -gt 0 ]; then
  ARGS+=("$@")
fi

exec "$SERVER_BIN" "${ARGS[@]}"
