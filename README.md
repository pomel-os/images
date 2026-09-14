# pomelos/images — Bazzite → bootable qcow2

Builds an OpenStack-ready Bazzite disk image with
[bootc-image-builder](https://github.com/osbuild/bootc-image-builder) (BIB).

Bazzite's published images are bootc images, so BIB writes a disk directly — no
ISO, no Anaconda. Source is `ghcr.io/ublue-os/bazzite-nvidia-open:stable`; swap
`SOURCE_IMAGE` for `bazzite-nvidia` or plain `bazzite`, and the `pomelos-`
prefixed tag with it.

The derived layer adds the two things upstream lacks: **cloud-init** (upstream
strips `/etc/passwd` to root with no password, so a plain BIB image has no login)
and **first-boot flatpak seeding** (upstream installs zero applications).

## Requirements

Fedora host with `podman` and `sudo`; `qemu-img`, `virt-install` and
`cloud-utils` to test. The VM needs network on first boot to fetch flatpaks.

## 1. Derived image

```sh
sudo podman build \
  --build-arg SOURCE_IMAGE=ghcr.io/ublue-os/bazzite-nvidia-open:stable \
  --build-arg CLOUD_USER=pomelos \
  -t localhost/pomelos-bazzite-nvidia-open:stable -f Containerfile .
```

## 2. qcow2

`--rootfs btrfs` is mandatory: Bazzite declares no default root filesystem, and
without it BIB refuses to generate a manifest.

```sh
mkdir -p output cache/store cache/rpmmd
sudo podman run --rm -it --privileged --pull=newer \
  --security-opt label=type:unconfined_t \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v "$PWD/disk.toml":/config.toml:ro \
  -v "$PWD/output":/output \
  -v "$PWD/cache/store":/store -v "$PWD/cache/rpmmd":/rpmmd \
  quay.io/centos-bootc/bootc-image-builder:latest \
  build --type qcow2 --rootfs btrfs \
        --chown "$(id -u):$(id -g)" --progress verbose \
        localhost/pomelos-bazzite-nvidia-open:stable
```

Result: `output/qcow2/disk.qcow2`. Swap `build` for `manifest` and drop the
`/output` mount to validate config in seconds without running osbuild.
