#!/usr/bin/bash
# Runs inside `podman build` against the upstream Bazzite image.
# files/ is already COPYed into place by the Containerfile; this only does the
# parts that need logic.
#
# Paths like installer/... refer to https://github.com/ublue-os/bazzite/tree/main
set -euo pipefail

: "${CLOUD_USER:=pomelos}"

log() { printf '\n=== %s\n' "$*"; }

# --- cloud-init --------------------------------------------------------------
# Upstream strips /etc/passwd down to root with no password
# (build_files/finalize), so without this the disk image is unloginable.
#
# Bazzite versionlocks a large part of its package set. Try the plain install
# first; only clear the locks if the transaction actually fails, so we do not
# silently loosen upstream's pinning when we do not have to.
log "layering cloud-init + growpart"
if ! dnf5 -y install --setopt=install_weak_deps=False \
        cloud-init cloud-utils-growpart gdisk; then
    echo "!!! install failed, retrying after 'versionlock clear'"
    dnf5 -y versionlock clear
    dnf5 -y install --setopt=install_weak_deps=False \
        cloud-init cloud-utils-growpart gdisk
fi

log "enabling cloud-init"
# Unit names moved in cloud-init 24.3: cloud-init.service was renamed to
# cloud-init-network.service, and cloud-init-main.service was added. Enable
# whichever units this build actually ships rather than assuming a fixed set.
#
# cloud-init.target is deliberately NOT in this list: it has no [Install]
# section (the cloud-init generator activates it at boot), so `systemctl enable`
# on it fails. The services below are WantedBy=cloud-init.target, which is what
# actually wires them up.
enabled_any=0
for unit in cloud-init-local.service \
            cloud-init-main.service \
            cloud-init-network.service \
            cloud-init.service \
            cloud-config.service \
            cloud-final.service; do
    if [ -e "/usr/lib/systemd/system/${unit}" ]; then
        if systemctl enable "${unit}"; then
            enabled_any=1
            printf '    enabled %s\n' "${unit}"
        else
            printf '    could not enable %s\n' "${unit}"
        fi
    fi
done

if [ "${enabled_any}" != 1 ]; then
    echo "!!! no cloud-init units could be enabled; check the package layout" >&2
    systemctl list-unit-files 'cloud*' >&2 || :
    exit 1
fi

sed -i "s/@CLOUD_USER@/${CLOUD_USER}/g" /etc/cloud/cloud.cfg.d/99-pomelos.cfg

# cloud-init's resizefs cannot grow a bootc root (it hardcodes "/", a composefs
# overlay), so growpart extends the partition and this extends the filesystem.
systemctl enable pomelos-growfs.service

# Flatpaks are seeded on first boot, not baked in: bootc discards a container
# image's /var at install time. See README "Flatpaks".
# The timer is what gets enabled; the service has no [Install] section.
systemctl enable pomelos-flatpak-seed.timer

# Leave flatpak-add-fedora-repos.service enabled — it creates the flathub remote
# the seeding installs from. (The ISO disables it; its /var arrives preconfigured.)

# /var is discarded at install, so this is only about not shipping the debris in
# a layer -- and about keeping `bootc container lint` quiet enough to notice a
# real warning.
log "cleaning up"
dnf5 clean all
rm -rf /var/cache/libdnf5 /var/cache/ldconfig /var/lib/dnf \
       /var/log/dnf5.log* /tmp/*
