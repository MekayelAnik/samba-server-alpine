# Use Alpine Linux
ARG ALPINE_VERSION=edge
ARG TZ=Asia/Dhaka
FROM alpine:$ALPINE_VERSION

LABEL author="MUHAMMAD MEKAYEL ANIK"
LABEL author_email="mekayel.anik@gmail.com"
LABEL github_url="https://github.com/MekayelAnik/samba-server-alpine"
LABEL licence="GPL-3.0"

ADD --chmod=555 ./scripts /usr/bin

RUN echo https://dl-cdn.alpinelinux.org/alpine/edge/main > /etc/apk/repositories && \
    echo https://dl-cdn.alpinelinux.org/alpine/edge/community >> /etc/apk/repositories && \
    apk --update-cache --no-cache upgrade && \
    apk add --update-cache --no-cache samba tzdata bash && \
    rm -rf /var/cache/apk/*

# Define service entrypoint
CMD ["/usr/bin/smbd.sh"]

