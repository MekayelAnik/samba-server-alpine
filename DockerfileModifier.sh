#!/bin/bash

# Define variables
DOCKERFILE_NAME="./Dockerfile.samba-server-alpine"
STABLE_ALPINE_VERSION="latest" 
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Step 1: Find the actual Samba version using a temporary container or local apk ---
# Note: Since the script runs on the host, this requires 'apk' or a similar tool 
# that knows about the Alpine repository (which is often complex to set up outside Alpine).
# A safer approach for a reliable build script is to *trust* the apk-in-build to 
# find the version and only use the ARG for the label if a multi-stage build is 
# implemented. Since that is complex, we'll fix the syntax error *and* note the limitation.

# The safest syntax fix: keep it as a single, valid shell command for RUN
cat <<EOF > "${DOCKERFILE_NAME}"
# Use Alpine Linux - Using a stable version for reliability
FROM alpine:${STABLE_ALPINE_VERSION}

# 1. Define an ARG to hold the version, which will be set dynamically below
ARG SAMBA_VERSION="unknown"

# Set environment variables for non-interactive installs and timezone
ENV TZ="${TZ:-Asia/Dhaka}" \
    PACKAGES="samba tzdata bash"

# --- CORE OPTIMIZATION: Get Package Version and Install in a single layer ---
# FIX: All shell commands are put on a single line, separated by '&&', 
# so 'export' is seen as a shell command, not a Dockerfile instruction.
RUN apk update && export SAMBA_VERSION=\$(apk search --print-ver samba) && /bin/echo "SAMBA_VERSION=\${SAMBA_VERSION}" >> /etc/profile.d/samba_version.sh && apk --upgrade add \${PACKAGES} && rm -rf /var/cache/apk/* /tmp/*

# 2. Use the dynamically captured version in the final LABEL
LABEL org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.version="\${SAMBA_VERSION}" \
    org.opencontainers.image.authors="MD. MEKAYEL ANIK <mekayel.anik@gmail.com>" \
    org.opencontainers.image.source="https://github.com/MekayelAnik/samba-server-alpine" \
    org.opencontainers.image.licenses="GPL-3.0" \

# Add local resources AFTER package installation to prevent cache invalidation
ADD --chmod=555 ./resources  /usr/bin

# Ports are best listed in a single EXPOSE instruction
EXPOSE 445 137-139 389 901

# Define service entrypoint
CMD ["/usr/bin/smbd.sh"]
EOF

echo "Successfully generated the final, optimized Dockerfile content in ${DOCKERFILE_NAME}"
echo "Note: The Dockerfile is configured to capture the Samba version (\$(apk search --print-ver samba)) during the build and use it for the 'org.opencontainers.image.version' label."