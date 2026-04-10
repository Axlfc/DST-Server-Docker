FROM cm2network/steamcmd:root

LABEL maintainer="DST-Server-Docker <noreply@example.com>"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV DST_DIR=/opt/dst_server
ENV DATA_DIR=/data

# Ensure steamcmd exists and is available in PATH for non-root users
RUN set -eux; \
    apt-get update -y; \
    apt-get install -y --no-install-recommends ca-certificates wget tar bzip2 lib32gcc-s1 lib32stdc++6 || true; \
    mkdir -p /opt/steamcmd; \
    if [ ! -f /opt/steamcmd/steamcmd.sh ]; then \
      wget -qO /tmp/steamcmd_linux.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz; \
      tar -xzf /tmp/steamcmd_linux.tar.gz -C /opt/steamcmd; \
      rm -f /tmp/steamcmd_linux.tar.gz; \
    fi; \
    ln -sf /opt/steamcmd/steamcmd.sh /usr/local/bin/steamcmd; \
    chmod +x /usr/local/bin/steamcmd; \
    rm -rf /var/lib/apt/lists/* || true

RUN useradd -m -s /bin/bash dst \
    && mkdir -p ${DST_DIR} ${DATA_DIR} \
    && chown -R dst:dst ${DST_DIR} ${DATA_DIR}

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER dst
WORKDIR /home/dst

EXPOSE 10999/udp 11000/udp 12346/udp 12347/udp

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
