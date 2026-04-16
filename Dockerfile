FROM cm2network/steamcmd:root

ENV DST_DIR=/opt/dst_server
ENV DATA_DIR=/data

RUN set -eux; \
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libcurl4-gnutls-dev libtinfo6 libcurl4 wget tar ca-certificates \
        libstdc++6 libgcc-s1 \
        libcurl4-gnutls-dev:i386 libtinfo6:i386 libcurl4:i386 \
        libstdc++6:i386 libgcc-s1:i386 lib32gcc-s1 lib32stdc++6 libc6-i386; \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p ${DST_DIR}/mods ${DATA_DIR} \
    && chown -R steam:steam ${DST_DIR} ${DATA_DIR}

COPY --chown=steam:steam docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER steam
WORKDIR /home/steam

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
