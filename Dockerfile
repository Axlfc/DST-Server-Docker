FROM cm2network/steamcmd:root

ENV DST_DIR=/opt/dst_server
ENV DATA_DIR=/data

# Instalación de dependencias necesarias para DST (x64 y x86)
# Klei recomienda varias librerías de 32 bits incluso para la versión de 64 bits
RUN set -eux; \
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libcurl4-gnutls-dev \
        libtinfo6 \
        libcurl4 \
        wget \
        tar \
        ca-certificates \
        libstdc++6 \
        libgcc-s1 \
        libsqlite3-0 \
        # Librerías i386 (32 bits)
        libcurl4-gnutls-dev:i386 \
        libtinfo6:i386 \
        libcurl4:i386 \
        libstdc++6:i386 \
        libgcc-s1:i386 \
        lib32gcc-s1 \
        lib32stdc++6 \
        libc6-i386 \
        libsqlite3-0:i386; \
    rm -rf /var/lib/apt/lists/*

# Crear directorios y ajustar permisos
RUN mkdir -p ${DST_DIR}/mods ${DATA_DIR} \
    && chown -R steam:steam ${DST_DIR} ${DATA_DIR}

COPY --chown=steam:steam docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER steam
WORKDIR /home/steam

# Exponer puertos por defecto (documentación)
# Master: 10999/udp, 10888/udp (shard), 27016/udp (steam), 8766/udp (auth)
# Caves: 11000/udp, 27017/udp (steam), 8767/udp (auth)

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
