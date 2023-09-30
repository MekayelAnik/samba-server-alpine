# Use Alpine Linux
ARG ALPINE_VERSION=edge
ARG TZ=Asia/Dhaka
FROM alpine:$ALPINE_VERSION

LABEL author="MUHAMMAD MEKAYEL ANIK"
LABEL author_email="mekayel.anik@gmail.com"
LABEL github_url="https://github.com/MekayelAnik/samba-server-alpine"
LABEL licence="GPL-3.0"

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
    rm -rf /var/cache/apk/*

# Define service entrypoint
CMD ["/usr/bin/smbd.sh"]

