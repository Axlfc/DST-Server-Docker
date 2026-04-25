#!/usr/bin/env bash
set -euo pipefail

DST_DIR="/opt/dst_server"
DATA_DIR="/data"
SHARD_NAME=${SHARD_NAME:-Master}
SKIP_UPDATE=${SKIP_UPDATE:-false}

echo "--- INICIANDO SHARD: $SHARD_NAME ---"

# -1. Verificaciones de Mods
MODS_SETUP="$DST_DIR/mods/dedicated_server_mods_setup.lua"
if [ -d "$MODS_SETUP" ]; then
    echo "ERROR: $MODS_SETUP es un directorio. Docker probablemente lo creó porque el archivo no existía en el host."
    echo "Asegúrate de que ./dedicated_server_mods_setup.lua existe en el host."
    exit 1
elif [ ! -f "$MODS_SETUP" ]; then
    echo "AVISO: No se encontró dedicated_server_mods_setup.lua en $MODS_SETUP. No se descargarán mods automáticamente."
else
    echo "✓ dedicated_server_mods_setup.lua detectado."
fi

# 0. Gestión de Configuración (Token y Password)
CLUSTER_PATH="$DATA_DIR/DoNotStarveTogether/Cluster_1"
mkdir -p "$CLUSTER_PATH"

# Token
if [ -f "$CLUSTER_PATH/cluster_token.txt" ]; then
    echo "Token detectado en cluster_token.txt."
elif [ ! -z "${CLUSTER_TOKEN:-}" ]; then
    echo "Configurando CLUSTER_TOKEN desde variable de entorno..."
    echo "$CLUSTER_TOKEN" > "$CLUSTER_PATH/cluster_token.txt"
else
    echo "AVISO: No se encontró CLUSTER_TOKEN. El servidor no será visible externamente."
fi

# Password (Inyectar en cluster.ini si existe la variable CLUSTER_PASSWORD)
if [ ! -z "${CLUSTER_PASSWORD:-}" ] && [ -f "$CLUSTER_PATH/cluster.ini" ]; then
    echo "Inyectando CLUSTER_PASSWORD en cluster.ini..."
    # Usamos sed para reemplazar o añadir la password en la sección [NETWORK]
    sed -i "s/^cluster_password =.*/cluster_password = $CLUSTER_PASSWORD/" "$CLUSTER_PATH/cluster.ini"
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
    echo "Esperando a que el Master descargue/verifique los binarios..."
    # Aumentamos el tiempo de espera por si la descarga es lenta
    TIMEOUT=60
    while [ ! -f "$DST_DIR/bin64/dontstarve_dedicated_server_nullrenderer_x64" ]; do
        if [ $TIMEOUT -le 0 ]; then
            echo "ERROR: Tiempo de espera agotado para los binarios."
            exit 1
        fi
        sleep 10
        TIMEOUT=$((TIMEOUT-1))
    done
    echo "¡Binarios detectados!"
fi

# 2. Actualización de Mods (Solo en el Master para evitar conflictos)
if [ "$SHARD_NAME" == "Master" ]; then
    echo "Actualizando mods..."
    cd "$DST_DIR/bin64"
    ./dontstarve_dedicated_server_nullrenderer_x64 -only_update_server_mods -persistent_storage_root /data -conf_dir DoNotStarveTogether -cluster Cluster_1 || echo "Aviso: La actualización de mods devolvió un código de salida no cero, continuando..."
fi

# 2b. Verificación de modoverrides.lua
if [ -f "$CLUSTER_PATH/modoverrides.lua" ]; then
    echo "✓ modoverrides.lua detectado en $CLUSTER_PATH."
elif [ -f "$CLUSTER_PATH/$SHARD_NAME/modoverrides.lua" ]; then
    echo "✓ modoverrides.lua detectado en $CLUSTER_PATH/$SHARD_NAME."
else
    echo "AVISO: No se encontró modoverrides.lua. Los mods no estarán activos aunque se hayan descargado."
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
