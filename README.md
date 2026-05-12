# DST Dedicated Server Docker (Master & Caves)

> ⚠️ **Unofficial community project.** Not affiliated with or endorsed by Klei Entertainment.

Este repositorio contiene una configuración optimizada y lista para usar de un servidor dedicado de **Don't Starve Together** utilizando Docker. Está diseñado para ser **idempotente** (siempre funciona igual) y **portable** entre Windows y Linux (CachyOS).

## 🚀 Características
- **Multi-shard:** Master y Caves funcionando en contenedores separados.
- **Binarios compartidos:** Usa un volumen compartido para no descargar el juego dos veces.
- **Auto-Update:** Descarga y actualiza el juego y los mods automáticamente al arrancar.
- **Optimizado:** Configurado para 8-16 jugadores con 8GB de RAM recomendados.
- **Dependencias Completas:** Incluye todas las librerías x64 y x86 necesarias para evitar fallos.

---

## 🛠️ Requisitos Previos

1. **Docker y Docker Compose:** Instalados en tu sistema.
2. **Cluster Token:** Necesitas un token de Klei para que el servidor sea visible.
   - Ve a [Klei Account](https://accounts.klei.com/account/game/servers?game=DontStarveTogether).
   - Crea un token y guárdalo.
3. **Puertos Abiertos (Router):**
   - `10999 UDP` (Master)
   - `11000 UDP` (Caves)
   - `10888 UDP` (Comunicación interna)
   - `27016 UDP` (Steam 1)
   - `27017 UDP` (Steam 2)
   - `8766 UDP` (Steam Auth 1)
   - `8767 UDP` (Steam Auth 2)

---

## 📂 Configuración para Windows y CachyOS (Dual Boot)

Para que el servidor mantenga el mismo progreso en ambos sistemas, lo ideal es tener este repositorio en un **disco secundario** accesible por ambos (ej. una partición NTFS o ExFAT).

### 1. Preparación
1. Clona este repositorio en tu disco compartido.
2. Crea un archivo `.env` en la raíz del proyecto basado en `.env.example`:
   ```bash
   CLUSTER_TOKEN=TU_TOKEN_DE_KLEI_AQUI
   CLUSTER_NAME=Mi Servidor DST
   CLUSTER_PASSWORD=tu_password_aqui
   ```

### 2. Cómo Levantar el Servidor
Independientemente de si estás en Windows (PowerShell/CMD) o Linux (Terminal), el comando es el mismo:

```bash
docker-compose up -d
```

- La primera vez tardará unos minutos en descargar los ~3GB del servidor.
- Para ver el progreso: `docker-compose logs -f`

### 3. Cómo Detener el Servidor
```bash
docker-compose stop
```

### 4. Cómo Actualizar el Servidor
Simplemente reinicia los contenedores. El script `docker-entrypoint.sh` comprobará si hay actualizaciones en Steam:
```bash
docker-compose restart
```

---

## ⚙️ Personalización

### 🏷️ Cambiar Nombre y Contraseña
Puedes cambiar el nombre y la contraseña del servidor de dos formas:

#### A. Usando el archivo `.env` (Recomendado)
Es la forma más sencilla. Solo tienes que editar el archivo `.env` en la raíz del proyecto:
```bash
CLUSTER_NAME=El nuevo nombre de mi servidor
CLUSTER_PASSWORD=una_contraseña_segura
```
Al reiniciar el servidor, estos valores se aplicarán automáticamente.

#### B. Edición Manual
Si prefieres editar los archivos directamente, puedes hacerlo en:
`dst-data/DoNotStarveTogether/Cluster_1/cluster.ini`

Busca estas líneas bajo la sección `[NETWORK]`:
```ini
cluster_name = La chica de la Boina
cluster_password = LaChicaDeLaBoina
```
*Nota: Si has configurado variables en el `.env`, estas sobrescribirán lo que pongas manualmente en el `cluster.ini` cada vez que el servidor arranque.*

### 🗺️ Ajustes del Mundo
Edita los archivos en `dst-data/DoNotStarveTogether/Cluster_1/`:
- `cluster.ini`: Otros ajustes como número de jugadores (`max_players`) o modo de juego (`game_mode`).
- `Master/worldgenoverride.lua`: Configuración del mapa de la superficie.
- `Caves/worldgenoverride.lua`: Configuración del mapa de las cuevas.

### 🔌 Gestión de Mods
Para añadir o quitar mods, debes seguir dos pasos:

1.  **Descarga (Setup):** Edita el archivo `dedicated_server_mods_setup.lua` en la raíz y añade una línea por cada mod:
    ```lua
    ServerModSetup("ID_DEL_MOD")
    ```
2.  **Activación y Configuración:** Edita `dst-data/DoNotStarveTogether/Cluster_1/modoverrides.lua` para activar el mod y configurar sus opciones:
    ```lua
    ["workshop-ID_DEL_MOD"] = {
        enabled = true,
        configuration_options = { ... }
    }
    ```
    *Nota: Si quitas un mod, asegúrate de eliminarlo de ambos archivos.*

### 🧠 Ajustar RAM (Memoria)
Si notas que el servidor necesita más (o menos) memoria, puedes ajustarlo en el archivo `docker-compose.yml`:

1.  Busca la sección `deploy: resources: limits: memory` para `dst-master` y `dst-caves`.
2.  Cambia el valor (ej. `4G` a `2G` o `8G` según tu necesidad).
3.  Reinicia el servidor para aplicar los cambios: `docker-compose up -d`.

## 📝 Notas Técnicas
- **Idempotencia:** El servidor usa volúmenes de Docker (`dst-bin` y `./dst-data`). Si borras los contenedores, el progreso y los binarios persisten.
- **Memoria:** Se han asignado límites de 4GB por contenedor (8GB en total). Puedes ajustarlos en `docker-compose.yml` si lo necesitas.
- **Propiedad de Archivos:** En Linux, Docker puede cambiar los permisos de `dst-data`. El script de inicio intenta manejar esto, pero asegúrate de que tu usuario tenga acceso a la partición compartida.
