#!/usr/bin/env bash
set -euo pipefail

DST_DIR="/opt/dst_server"
DATA_DIR="/data"
SHARD_NAME=${SHARD_NAME:-Master}
SKIP_UPDATE=${SKIP_UPDATE:-false}

echo "--- INICIANDO SHARD: $SHARD_NAME ---"

# -1. Verificación del archivo de mods (comprobamos /tmp, que es el mount real)
if [ -f "/tmp/dedicated_server_mods_setup.lua" ]; then
    echo "✓ dedicated_server_mods_setup.lua detectado."
else
    echo "AVISO: No se encontró dedicated_server_mods_setup.lua en /tmp. No se descargarán mods automáticamente."
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
    # SteamCMD falla con 'Missing configuration' o estado 0x202/0x626 en volúmenes vacíos.
    # Reintentamos hasta 3 veces, workaround conocido para este bug de Steam.
    for attempt in 1 2 3; do
        /home/steam/steamcmd/steamcmd.sh +runscript /tmp/dst_update.txt && break
        echo "SteamCMD falló (intento $attempt/3), reintentando..."
        sleep 5
    done
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
    # === Restaurar dedicated_server_mods_setup.lua (SteamCMD lo sobreescribe) ===
    if [ -f "/tmp/dedicated_server_mods_setup.lua" ]; then
        echo "Restaurando dedicated_server_mods_setup.lua..."
        cp /tmp/dedicated_server_mods_setup.lua "$DST_DIR/mods/dedicated_server_mods_setup.lua"
    fi
    # === FIX: Crear carpetas de Steam para Workshop (Local a los binarios) ===
    echo "Preparando directorios de Steam para Workshop en $DST_DIR/bin64..."
    mkdir -p "$DST_DIR/bin64/steamapps/workshop/content/322330"
    mkdir -p "$DST_DIR/bin64/steamapps/workshop/staging"
    mkdir -p "$DST_DIR/bin64/config"

    cat > "$DST_DIR/bin64/steamapps/libraryfolders.vdf" << 'EOF'
"libraryfolders"
{
    "contentstatsid"    "-1"
    "1"
    {
        "path"    "/opt/dst_server"
        "label"    ""
        "totalsize"    "0"
        "update_clean_bytes_tally"    "0"
        "time_last_update_corruption"    "0"
        "apps"
        {
            "322330"    "0"
        }
    }
}
EOF
    chmod -R 755 "$DST_DIR/bin64/steamapps" "$DST_DIR/bin64/config"
    # === FIN FIX ===
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
