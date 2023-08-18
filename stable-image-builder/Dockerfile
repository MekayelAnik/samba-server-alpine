# Use Alpine Linux
ARG ALPINE_VERSION=latest
FROM alpine:$ALPINE_VERSION
ARG DEBIAN_FRONTEND=noninteractive 
ARG TZ=Asia/Dhaka

COPY --chmod=555 ./constructUsers.sh /usr/bin/
COPY --chmod=555 ./constructDir.sh /usr/bin
COPY --chmod=555 ./constructConf.sh /usr/bin
COPY --chmod=555 ./banner.sh /usr/bin
COPY --chmod=555 ./smbd.sh /usr/bin
COPY --chmod=444 ./build-timestamp /usr/bin
RUN echo https://dl-cdn.alpinelinux.org/alpine/edge/main > /etc/apk/repositories && \
    echo https://dl-cdn.alpinelinux.org/alpine/edge/community >> /etc/apk/repositories && \
    apk --update-cache --no-cache upgrade && \
    apk add --update-cache --no-cache samba tzdata bash && \
    rm -rf /var/cache/apk/* && \
    rm -rf /etc/samba/*

# Define service entrypoint
CMD ["/usr/bin/smbd.sh"]

