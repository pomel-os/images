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

CI already publishes this on every push to `main` and weekly
(`.github/workflows/build.yml`), so you can skip straight to step 2 with
`ghcr.io/pomel-os/pomelos-bazzite-nvidia-open:stable`. It is cosign-signed:

```sh
cosign verify --key cosign.pub ghcr.io/pomel-os/pomelos-bazzite-nvidia-open:stable
```

To build it yourself:

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

## Sunshine

`pomelos-sunshine.service` runs Sunshine as root from boot, so clients can
stream the login screen. Settings live in `/etc/sunshine/sunshine.conf`; the
web UI is on `https://<host>:47990`.

Audio comes from the user's PipeWire (UID 1000 assumed), so there is none until
someone logs in. Sunshine is a patched build from
[pomel-os/copr_sunshine](https://github.com/pomel-os/copr_sunshine) (release and
checksum pinned in `derive.sh`) that keeps retrying the audio server, so a stream
started at the login screen gets audio once the user logs in.

[sunshine_virt_display](https://github.com/frostplexx/sunshine_virt_display)
(`pomelos-sunshine-vd.service`, pinned in `derive.sh`) gives each client a virtual
display at its own resolution and refresh rate, via Sunshine's `global_prep_cmd`.

## Testing on an existing VM

Run a local registry once, then build and push on each change:

```sh
podman run -d --name registry -p 5000:5000 docker.io/library/registry:2
podman build -t localhost:5000/pomelos-test -f Containerfile .
podman push --tls-verify=false localhost:5000/pomelos-test
```

On the VM, `<host>` is the address it reaches the host on (the default gateway
with user-mode networking, `192.168.122.1` on libvirt's default network):

```sh
sudo tee /etc/containers/registries.conf.d/50-dev.conf <<'CONF'
[[registry]]
location = "<host>:5000"
insecure = true
CONF
sudo bootc switch <host>:5000/pomelos-test   # once
sudo bootc upgrade --apply                   # after each push
```

Back to the published image:
`sudo bootc switch ghcr.io/pomel-os/pomelos-bazzite-nvidia-open:stable`.
