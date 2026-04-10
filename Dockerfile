FROM cm2network/steamcmd:root

LABEL maintainer="DST-Server-Docker <noreply@example.com>"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV DST_DIR=/opt/dst_server
ENV DATA_DIR=/data

RUN useradd -m -s /bin/bash dst \
    && mkdir -p ${DST_DIR} ${DATA_DIR} \
    && chown -R dst:dst ${DST_DIR} ${DATA_DIR}

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER dst
WORKDIR /home/dst

EXPOSE 10999/udp 11000/udp 12346/udp 12347/udp

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
