#!/usr/bin/env fish
# ============================================================
# DST Server Management Scripts - Fish Shell (CachyOS)
# Uso: source dst-scripts.fish
# O copia las funciones que necesites a tu ~/.config/fish/config.fish
# ============================================================

set DST_DIR ~/Almacenamiento_SSD/Documents/git/DST-Server-Docker
set DST_DATA $DST_DIR/dst-data/DoNotStarveTogether/Cluster_1
set MODS_SETUP $DST_DIR/dedicated_server_mods_setup.lua
set MODOVERRIDES $DST_DATA/modoverrides.lua

# ------------------------------------------------------------
# dst-up: Levantar el servidor
# ------------------------------------------------------------
function dst-up
    cd $DST_DIR
    docker compose up -d
    echo "✓ Servidor arrancado. Logs:"
    docker compose logs -f --tail=50
end

# ------------------------------------------------------------
# dst-down: Parar el servidor
# ------------------------------------------------------------
function dst-down
    cd $DST_DIR
    docker compose down
    echo "✓ Servidor parado."
end

# ------------------------------------------------------------
# dst-restart: Parar y arrancar aplicando cambios de configuración
# NOTA: No usa 'docker compose restart' porque ese comando NO re-ejecuta
# el entrypoint — los cambios en mods/config no se aplicarían.
# ------------------------------------------------------------
function dst-restart
    cd $DST_DIR
    docker compose down
    docker compose up -d
    echo "✓ Reiniciando... logs:"
    docker compose logs -f --tail=50
end

# ------------------------------------------------------------
# dst-rebuild: Rebuild completo de imagen (cuando cambias Dockerfile
# o docker-entrypoint.sh). También limpia el centinela .master_ready
# para que Caves no arranque antes de que Master termine su setup.
# ------------------------------------------------------------
function dst-rebuild
    cd $DST_DIR
    docker compose down
    # Limpiar centinela del volumen dst-bin para evitar race condition
    # entre Master y Caves en el arranque tras rebuild
    docker run --rm -v dst-server-docker_dst-bin:/vol alpine sh -c "rm -f /vol/.master_ready" 2>/dev/null
    docker compose build
    docker compose up -d
    echo "✓ Rebuild completo. Logs:"
    docker compose logs -f --tail=50
end

# ------------------------------------------------------------
# dst-logs: Ver logs en tiempo real
# Uso: dst-logs          → Master
#      dst-logs caves    → Caves
#      dst-logs all      → Ambos intercalados
# ------------------------------------------------------------
function dst-logs
    cd $DST_DIR
    if test (count $argv) -ge 1
        if test $argv[1] = all
            docker compose logs -f --tail=50
            return
        end
        docker compose logs dst-$argv[1] -f --tail=50
    else
        docker compose logs dst-master -f --tail=50
    end
end

# ------------------------------------------------------------
# dst-status: Estado de los contenedores con healthcheck
# ------------------------------------------------------------
function dst-status
    cd $DST_DIR
    docker compose ps
    echo ""
    echo "=== Healthcheck Master ==="
    docker inspect dst-master --format='Estado: {{.State.Health.Status}}' 2>/dev/null
    docker inspect dst-master --format='Último resultado: {{(index .State.Health.Log 0).Output}}' 2>/dev/null
end

# ------------------------------------------------------------
# dst-health: Ver estado del healthcheck en detalle
# ------------------------------------------------------------
function dst-health
    echo "=== Healthcheck dst-master ==="
    docker inspect dst-master --format='
Estado:   {{.State.Health.Status}}
Fallos:   {{.State.Health.FailingStreak}}
Último:   {{(index .State.Health.Log 0).Output}}' 2>/dev/null \
        || echo "Contenedor no encontrado o sin healthcheck."
end

# ------------------------------------------------------------
# dst-save: Forzar guardado del mundo via consola Lua de DST
# ------------------------------------------------------------
function dst-save
    cd $DST_DIR
    docker exec dst-master bash -c 'echo "c_save()" > /proc/$(pgrep -f dontstarve_dedicated)/fd/0' 2>/dev/null \
        || echo "⚠ No se pudo enviar c_save(). Comprueba que el servidor está corriendo."
    echo "✓ Guardado forzado enviado al master."
end

# ------------------------------------------------------------
# dst-fix-serverini: Reparar server.ini corrupto (solo [ACCOUNT])
# Útil cuando DST sobreescribe el server.ini con uno incompleto.
# ------------------------------------------------------------
function dst-fix-serverini
    echo "Reparando server.ini de Master..."
    printf '%s\n' \
        '[NETWORK]' \
        'server_port = 10999' \
        '' \
        '[SHARD]' \
        'is_master = true' \
        'name = Master' \
        'id = 1' \
        '' \
        '[STEAM]' \
        'master_server_port = 27016' \
        'authentication_port = 8766' \
        '' \
        '[ACCOUNT]' \
        'encode_user_path = true' \
        > $DST_DATA/Master/server.ini
    echo "✓ Master/server.ini reparado."

    echo "Reparando server.ini de Caves..."
    printf '%s\n' \
        '[NETWORK]' \
        'server_port = 11000' \
        '' \
        '[SHARD]' \
        'is_master = false' \
        'name = Caves' \
        'id = 2' \
        'master_ip = dst-master' \
        'master_port = 10888' \
        '' \
        '[STEAM]' \
        'master_server_port = 27017' \
        'authentication_port = 8767' \
        '' \
        '[ACCOUNT]' \
        'encode_user_path = true' \
        > $DST_DATA/Caves/server.ini
    echo "✓ Caves/server.ini reparado."
    echo ""
    echo "→ Reinicia el servidor: dst-restart"
end

# ------------------------------------------------------------
# dst-mod-add: Añadir un mod por workshop ID
# Uso: dst-mod-add 943773166
# ------------------------------------------------------------
function dst-mod-add
    if test (count $argv) -lt 1
        echo "Uso: dst-mod-add <workshop_id>"
        return 1
    end
    set mod_id $argv[1]

    # grep -w busca el ID como palabra completa, evita falsos positivos
    # con IDs que sean substring de otros
    if not grep -qw $mod_id $MODS_SETUP
        echo "ServerModSetup(\"$mod_id\")" >> $MODS_SETUP
        echo "✓ Mod $mod_id añadido a dedicated_server_mods_setup.lua"
    else
        echo "! Mod $mod_id ya estaba en dedicated_server_mods_setup.lua"
    end

    if not grep -qw $mod_id $MODOVERRIDES
        set tmp (mktemp)
        # Buffer todas las líneas e inserta la nueva entrada justo antes de la
        # ÚLTIMA línea (el '}' de cierre de la tabla raíz), evitando confundirse
        # con '}' anidados de entradas con configuration_options.
        awk -v id="$mod_id" '
            { lines[NR] = $0 }
            END {
                for (i = 1; i < NR; i++) print lines[i]
                print "    [\"workshop-" id "\"] = { enabled = true },"
                print lines[NR]
            }
        ' $MODOVERRIDES > $tmp
        mv $tmp $MODOVERRIDES
        echo "✓ Mod $mod_id añadido a modoverrides.lua"
    else
        echo "! Mod $mod_id ya estaba en modoverrides.lua"
    end

    echo ""
    echo "→ Reinicia el servidor para aplicar: dst-restart"
end

# ------------------------------------------------------------
# dst-mod-remove: Quitar un mod por workshop ID
# Uso: dst-mod-remove 943773166
# ------------------------------------------------------------
function dst-mod-remove
    if test (count $argv) -lt 1
        echo "Uso: dst-mod-remove <workshop_id>"
        return 1
    end
    set mod_id $argv[1]

    # Patrón exacto para no borrar IDs que sean substring del ID objetivo
    if grep -qw $mod_id $MODS_SETUP
        sed -i "/ServerModSetup(\"$mod_id\")/d" $MODS_SETUP
        echo "✓ Mod $mod_id eliminado de dedicated_server_mods_setup.lua"
    else
        echo "! Mod $mod_id no estaba en dedicated_server_mods_setup.lua"
    end

    if grep -qw $mod_id $MODOVERRIDES
        sed -i "/workshop-$mod_id/d" $MODOVERRIDES
        echo "✓ Mod $mod_id eliminado de modoverrides.lua"
    else
        echo "! Mod $mod_id no estaba en modoverrides.lua"
    end

    echo ""
    echo "→ Reinicia el servidor para aplicar: dst-restart"
end

# ------------------------------------------------------------
# dst-mod-list: Listar mods activos y detectar desincronizaciones
# ------------------------------------------------------------
function dst-mod-list
    echo "=== Mods en dedicated_server_mods_setup.lua ==="
    set setup_ids (grep -oP '(?<=ServerModSetup\(")[0-9]+(?="\))' $MODS_SETUP)
    for id in $setup_ids
        echo "  • $id"
    end

    echo ""
    echo "=== Mods habilitados en modoverrides.lua ==="
    set override_ids (grep 'enabled = true' $MODOVERRIDES | grep -oP 'workshop-\K[0-9]+')
    for id in $override_ids
        echo "  • $id"
    end

    # Detectar desincronizaciones entre ambos ficheros
    echo ""
    echo "=== Comprobando sincronización ==="
    set issues 0
    for id in $setup_ids
        if not contains $id $override_ids
            echo "  ⚠ $id está en mods_setup pero NO en modoverrides"
            set issues (math $issues + 1)
        end
    end
    for id in $override_ids
        if not contains $id $setup_ids
            echo "  ⚠ $id está en modoverrides pero NO en mods_setup"
            set issues (math $issues + 1)
        end
    end
    if test $issues -eq 0
        echo "  ✓ Ambos ficheros están sincronizados."
    end
end

# ------------------------------------------------------------
# dst-console: Abrir shell interactiva del contenedor master
# ------------------------------------------------------------
function dst-console
    cd $DST_DIR
    docker exec -it dst-master bash
end

# ------------------------------------------------------------
# dst-clean-legacy: Quitar los 4 mods legacy sin modinfo.lua
# (347079953, 362175979, 375850593, 458940297)
# ------------------------------------------------------------
function dst-clean-legacy
    for id in 347079953 362175979 375850593 458940297
        dst-mod-remove $id
    end
    echo ""
    echo "→ Mods legacy eliminados. Reinicia con: dst-restart"
end

echo "✓ DST scripts cargados. Comandos disponibles:"
echo "  dst-up               Arrancar servidor"
echo "  dst-down             Parar servidor"
echo "  dst-restart          Parar y arrancar (aplica cambios de config/mods)"
echo "  dst-rebuild          Rebuild completo de imagen"
echo "  dst-logs [caves|all] Ver logs en tiempo real"
echo "  dst-status           Estado de contenedores + healthcheck"
echo "  dst-health           Detalle del healthcheck de Master"
echo "  dst-save             Forzar guardado (c_save)"
echo "  dst-fix-serverini    Reparar server.ini corrupto de Master/Caves"
echo "  dst-mod-add ID       Añadir mod por workshop ID"
echo "  dst-mod-remove ID    Quitar mod"
echo "  dst-mod-list         Listar mods + comprobar sincronización"
echo "  dst-console          Shell del contenedor master"
echo "  dst-clean-legacy     Quitar mods legacy sin modinfo.lua"
