#!/usr/bin/env bash
set -euo pipefail

DST_DIR="/opt/dst_server"
DATA_DIR="/data"
SHARD_NAME=${SHARD_NAME:-Master}
SKIP_UPDATE=${SKIP_UPDATE:-false}

echo "--- INICIANDO SHARD: $SHARD_NAME ---"

# 0. Gestión del Token
CLUSTER_PATH="$DATA_DIR/DoNotStarveTogether/Cluster_1"
mkdir -p "$CLUSTER_PATH"
if [ ! -z "${CLUSTER_TOKEN:-}" ]; then
    echo "Configurando CLUSTER_TOKEN..."
    echo "$CLUSTER_TOKEN" > "$CLUSTER_PATH/cluster_token.txt"
fi

# 1. Instalación / Actualización de Binarios
if [ "$SKIP_UPDATE" == "false" ]; then
    echo "Preparando script de actualización para SteamCMD..."
    
    cat << EOF > /tmp/dst_update.txt
@sSteamCmdForcePlatformType linux
force_install_dir $DST_DIR
login anonymous
app_update 343050 validate
quit
EOF

    echo "Ejecutando actualización (esto puede tardar)..."
    /home/steam/steamcmd/steamcmd.sh +runscript /tmp/dst_update.txt
else
    echo "Esperando a que el Master descargue los binarios..."
    until [ -f "$DST_DIR/bin64/dontstarve_dedicated_server_nullrenderer_x64" ]; do
        sleep 5
    done
    echo "¡Binarios detectados!"
fi

# 2. Actualización de Mods (Solo en el Master para evitar conflictos de escritura simultánea)
if [ "$SHARD_NAME" == "Master" ]; then
    echo "Actualizando mods..."
    cd "$DST_DIR/bin64"
    ./dontstarve_dedicated_server_nullrenderer_x64 -only_update_server_mods -persistent_storage_root /data -conf_dir DoNotStarveTogether -cluster Cluster_1
fi

# 3. Enlaces de librerías (Necesario para 64 bits)
mkdir -p /home/steam/.steam/sdk64
ln -sf /home/steam/steamcmd/linux64/steamclient.so /home/steam/.steam/sdk64/steamclient.so

# 4. Ejecución
cd "$DST_DIR/bin64"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:.:${DST_DIR}/bin64/lib64"

echo "Lanzando servidor DST ($SHARD_NAME)..."
exec ./dontstarve_dedicated_server_nullrenderer_x64 \
    -console \
    -persistent_storage_root /data \
    -conf_dir DoNotStarveTogether \
    -cluster Cluster_1 \
    -shard "$SHARD_NAME"
