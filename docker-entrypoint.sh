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

else
    # Caves: esperar a que Master haya dejado los binarios Y los mods listos.
    # Usamos un fichero centinela que Master crea al terminar su setup.
    echo "Esperando a que Master termine la instalación de binarios y mods..."
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
    echo "¡Master listo (binarios y mods disponibles)!"
fi

# 2. Descarga de mods via SteamCMD (Solo en el Master)
if [ "$SHARD_NAME" == "Master" ]; then
    # app_update validate puede haber borrado dedicated_server_mods_setup.lua; restaurarlo
    if [ -f "$MODS_SETUP_SRC" ]; then
        echo "Restaurando dedicated_server_mods_setup.lua..."
        cp "$MODS_SETUP_SRC" "$DST_DIR/mods/dedicated_server_mods_setup.lua"
    fi

    MODS_FILE="$DST_DIR/mods/dedicated_server_mods_setup.lua"
    if [ -f "$MODS_FILE" ]; then
        MOD_IDS=$(grep -oP '(?<=ServerModSetup\(")[0-9]+(?="\))' "$MODS_FILE" || true)

        if [ -n "$MOD_IDS" ]; then
            echo "Descargando mods via SteamCMD..."
            {
                echo "@sSteamCmdForcePlatformType linux"
                echo "login anonymous"
                for MOD_ID in $MOD_IDS; do
                    echo "workshop_download_item 322330 $MOD_ID"
                done
                echo "quit"
            } > /tmp/dst_mods.txt

            /home/steam/steamcmd/steamcmd.sh +runscript /tmp/dst_mods.txt \
                || echo "AVISO: Algún mod pudo no descargarse correctamente."

            WORKSHOP_DIR="/home/steam/.steam/steam/steamapps/workshop/content/322330"
            echo "Copiando mods a $DST_DIR/mods/..."
            for MOD_ID in $MOD_IDS; do
                MOD_SRC="$WORKSHOP_DIR/$MOD_ID"
                MOD_DST="$DST_DIR/mods/workshop-$MOD_ID"
                if [ -d "$MOD_SRC" ]; then
                    echo "  ✓ Copiando mod $MOD_ID..."
                    rm -rf "$MOD_DST"
                    cp -r "$MOD_SRC" "$MOD_DST"
                else
                    echo "  ✗ AVISO: No se encontró el mod $MOD_ID en $MOD_SRC"
                fi
            done
        else
            echo "AVISO: No se encontraron IDs de mods en $MODS_FILE."
        fi
    fi

    # Centinela: indicar a Caves que binarios y mods están listos
    touch "$DST_DIR/.master_ready"
    echo "✓ Centinela .master_ready creado."
fi

# 2b. Propagar modoverrides.lua al directorio del shard
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

# 2c. Generar server.ini del shard si no existe o está vacío
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

# 3. Enlaces de librerías
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
    -shard "$SHARD_NAME" \
    -skip_update_server_mods
