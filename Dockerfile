FROM cm2network/steamcmd:root

LABEL maintainer="DST-Server-Docker <noreply@example.com>"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV DST_DIR=/opt/dst_server
ENV DATA_DIR=/data

# Install DST dependencies (32-bit libraries)
RUN set -eux; \
    dpkg --add-architecture i386; \
    apt-get update -y; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        tar \
        bzip2 \
        lib32gcc-s1 \
        lib32stdc++6 \
        libc6-i386 \
        libcurl4-gnutls-dev:i386 \
        libtinfo6:i386; \
    rm -rf /var/lib/apt/lists/* || true

# The base image cm2network/steamcmd:root already has steamcmd in /home/steam/steamcmd/steamcmd.sh
RUN mkdir -p /opt/steamcmd && \
    ln -s /home/steam/steamcmd/steamcmd.sh /usr/local/bin/steamcmd

RUN useradd -m -s /bin/bash dst \
    && mkdir -p ${DST_DIR} ${DATA_DIR} \
    && chown -R dst:dst ${DST_DIR} ${DATA_DIR} /home/steam/steamcmd

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER dst
WORKDIR /home/dst

EXPOSE 10999/udp 11000/udp 12346/udp 12347/udp

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
