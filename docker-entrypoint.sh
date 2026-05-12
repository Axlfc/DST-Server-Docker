#!/usr/bin/env bash
set -euo pipefail

DST_DIR="/opt/dst_server"
DATA_DIR="/data"
SHARD_NAME=${SHARD_NAME:-Master}
SKIP_UPDATE=${SKIP_UPDATE:-false}

echo "--- INICIANDO SHARD: $SHARD_NAME ---"

# -1. Verificación del archivo de mods
MODS_SETUP_SRC="/tmp/dedicated_server_mods_setup.lua"
if [ -f "$MODS_SETUP_SRC" ]; then
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
elif [ -n "${CLUSTER_TOKEN:-}" ]; then
    echo "Configurando CLUSTER_TOKEN desde variable de entorno..."
    echo "$CLUSTER_TOKEN" > "$CLUSTER_PATH/cluster_token.txt"
else
    echo "AVISO: No se encontró CLUSTER_TOKEN. El servidor no será visible externamente."
fi

# Name & Password
if [ -f "$CLUSTER_PATH/cluster.ini" ]; then
    if [ -n "${CLUSTER_NAME:-}" ]; then
        echo "Inyectando CLUSTER_NAME en cluster.ini..."
        sed -i "s/^cluster_name =.*/cluster_name = $CLUSTER_NAME/" "$CLUSTER_PATH/cluster.ini"
    fi
    if [ -n "${CLUSTER_PASSWORD:-}" ]; then
        echo "Inyectando CLUSTER_PASSWORD en cluster.ini..."
        sed -i "s/^cluster_password =.*/cluster_password = $CLUSTER_PASSWORD/" "$CLUSTER_PATH/cluster.ini"
    fi
fi

# Symlink steamclient.so
mkdir -p /home/steam/.steam/sdk64
ln -sf /home/steam/steamcmd/linux64/steamclient.so /home/steam/.steam/sdk64/steamclient.so
echo "✓ Symlink steamclient.so configurado."

# Pre-crear estructura de directorios de Steam y libraryfolders.vdf.
# Sin esto, cuando SteamCMD se reinicia a sí mismo (auto-update) pierde
# el contexto de force_install_dir y no encuentra las library folders.
STEAM_ROOT="/home/steam/.steam/steam"
mkdir -p "$STEAM_ROOT/steamapps"
mkdir -p "$DST_DIR"

if [ ! -f "$STEAM_ROOT/steamapps/libraryfolders.vdf" ]; then
    echo "Creando libraryfolders.vdf..."
    cat > "$STEAM_ROOT/steamapps/libraryfolders.vdf" << 'EOF'
"libraryfolders"
{
    "0"
    {
        "path"      "/home/steam/.steam/steam"
        "label"     ""
        "totalsize" "0"
        "apps"      {}
    }
    "1"
    {
        "path"      "/opt/dst_server"
        "label"     ""
        "totalsize" "0"
        "apps"      {}
    }
}
EOF
    echo "✓ libraryfolders.vdf creado."
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
    for attempt in 1 2 3; do
        /home/steam/steamcmd/steamcmd.sh +runscript /tmp/dst_update.txt && break
        echo "SteamCMD falló (intento $attempt/3), reintentando..."
        sleep 5
    done

    # app_update validate puede haber borrado dedicated_server_mods_setup.lua; restaurarlo
    if [ -f "$MODS_SETUP_SRC" ]; then
        echo "Restaurando dedicated_server_mods_setup.lua..."
        cp "$MODS_SETUP_SRC" "$DST_DIR/mods/dedicated_server_mods_setup.lua"
    fi

    # Centinela para Caves
    touch "$DST_DIR/.master_ready"
    echo "✓ Centinela .master_ready creado."

else
    echo "Esperando a que Master termine la instalación de binarios..."
    TIMEOUT=120
    while [ ! -f "$DST_DIR/.master_ready" ]; do
        if [ $TIMEOUT -le 0 ]; then
            echo "ERROR: Tiempo de espera agotado esperando .master_ready."
            exit 1
        fi
        echo "  ...esperando .master_ready ($TIMEOUT intentos restantes)"
        sleep 5
        TIMEOUT=$((TIMEOUT - 1))
    done
    echo "¡Master listo!"
fi

# 2. Propagar modoverrides.lua al directorio del shard
SHARD_PATH="$CLUSTER_PATH/$SHARD_NAME"
mkdir -p "$SHARD_PATH"
if [ -f "$CLUSTER_PATH/modoverrides.lua" ]; then
    echo "Propagando modoverrides.lua a $SHARD_PATH/..."
    cp "$CLUSTER_PATH/modoverrides.lua" "$SHARD_PATH/modoverrides.lua"
    echo "✓ modoverrides.lua copiado a $SHARD_PATH."
elif [ -f "$SHARD_PATH/modoverrides.lua" ]; then
    echo "✓ modoverrides.lua ya existe en $SHARD_PATH."
else
    echo "AVISO: No se encontró modoverrides.lua. Los mods no estarán activos."
fi

# 3. Generar server.ini del shard si no existe o está vacío
SERVER_INI="$SHARD_PATH/server.ini"
if [ ! -s "$SERVER_INI" ]; then
    echo "Generando $SERVER_INI..."
    if [ "$SHARD_NAME" == "Master" ]; then
        cat > "$SERVER_INI" << 'SERVEREOF'
[NETWORK]
server_port = 10999

[SHARD]
is_master = true
name = Master
id = 1

[STEAM]
master_server_port = 27016
authentication_port = 8766
SERVEREOF
    else
        cat > "$SERVER_INI" << 'SERVEREOF'
[NETWORK]
server_port = 11000

[SHARD]
is_master = false
name = Caves
id = 2
master_ip = dst-master
master_port = 10888

[STEAM]
master_server_port = 27017
authentication_port = 8767
SERVEREOF
    fi
    echo "✓ $SERVER_INI generado."
fi

# 4. Ejecución
# Sin -skip_update_server_mods: DST descarga/verifica los mods al arrancar.
cd "$DST_DIR/bin64"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:.:${DST_DIR}/bin64/lib64"

echo "Lanzando servidor DST ($SHARD_NAME)..."
exec ./dontstarve_dedicated_server_nullrenderer_x64 \
    -console \
    -persistent_storage_root /data \
    -conf_dir DoNotStarveTogether \
    -cluster Cluster_1 \
    -shard "$SHARD_NAME"
