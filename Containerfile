# Adds cloud-init (upstream ships no user at all) and first-boot flatpak
# seeding. See README.md.

ARG SOURCE_IMAGE=ghcr.io/ublue-os/bazzite-nvidia-open:stable
FROM ${SOURCE_IMAGE}

ARG CLOUD_USER=pomelos

# COPY rather than --mount=type=bind: copied files get container SELinux labels,
# so the build needs no --security-opt label=disable, and COPY is content-hashed
# so edits invalidate the cache. files/ mirrors its destination paths.
COPY files/ /
COPY derive.sh /tmp/derive.sh

RUN env CLOUD_USER="${CLOUD_USER}" /tmp/derive.sh && rm -f /tmp/derive.sh

RUN --mount=type=tmpfs,target=/run --network=none bootc container lint
