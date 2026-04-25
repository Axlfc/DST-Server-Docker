# DST Dedicated Server Docker (Master & Caves)

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
   - `27016-27017 UDP` (Steam)
   - `8766-8767 UDP` (Steam Auth)

---

## 📂 Configuración para Windows y CachyOS (Dual Boot)

Para que el servidor mantenga el mismo progreso en ambos sistemas, lo ideal es tener este repositorio en un **disco secundario** accesible por ambos (ej. una partición NTFS o ExFAT).

### 1. Preparación
1. Clona este repositorio en tu disco compartido.
2. Crea un archivo `.env` en la raíz del proyecto basado en `.env.example`:
   ```bash
   CLUSTER_TOKEN=pds-tu-token-aqui
   CLUSTER_PASSWORD=LaChicaDeLaBoina
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

- **Mods:** Añade los IDs de los mods en `dedicated_server_mods_setup.lua`.
- **Ajustes del Mundo:** Edita los archivos en `dst-data/DoNotStarveTogether/Cluster_1/`:
  - `cluster.ini`: Nombre del server, contraseña (`LaChicaDeLaBoina`), número de jugadores.
  - `Master/worldgenoverride.lua`: Configuración del mapa de la superficie.
  - `Caves/worldgenoverride.lua`: Configuración del mapa de las cuevas.

## 📝 Notas Técnicas
- **Idempotencia:** El servidor usa volúmenes de Docker (`dst-bin` y `./dst-data`). Si borras los contenedores, el progreso y los binarios persisten.
- **Memoria:** Se han asignado límites de 4GB por contenedor (8GB en total). Puedes ajustarlos en `docker-compose.yml` si lo necesitas.
- **Propiedad de Archivos:** En Linux, Docker puede cambiar los permisos de `dst-data`. El script de inicio intenta manejar esto, pero asegúrate de que tu usuario tenga acceso a la partición compartida.
