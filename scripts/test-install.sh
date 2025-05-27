#!/usr/bin/env bash

# This script can be used to test the installer quickly. To use it, you need
# the following:
# - create an EFI partition with the filesystem label "TESTING-EFI"
# - create a root partition with the partition label "testing-root"
# To install, connect to Wi-Fi, then run this script as
# `sudo /x1e-nixos-config/scripts/test-install.sh`.

set -ex

if ! mountpoint /mnt; then
    yes | mkfs.ext4 -L root /dev/disk/by-partlabel/testing-root
    mount /dev/disk/by-label/root /mnt
    mkdir -p /mnt/boot
    mount /dev/disk/by-label/TESTING-EFI /mnt/boot
fi

flake="/tmp/x1e-nixos-config"
cp -r "$(readlink /x1e-nixos-config)" "$flake"
sed -i s/SYSTEM_DRV/TESTING-EFI/ "$flake"/examples/flake-based-config/configuration.nix

nixos-install --root /mnt --no-channel-copy --no-root-password --flake "${flake}#system"
