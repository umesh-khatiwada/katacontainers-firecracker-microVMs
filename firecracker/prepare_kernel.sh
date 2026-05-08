#!/bin/bash
set -euo pipefail

SOURCE_KERNEL="/boot/vmlinuz-$(uname -r)"
TARGET_KERNEL="/home/umesh-pc/fc-demo/vmlinux.bin"
EXTRACTOR="/usr/src/linux-hwe-6.17-headers-6.17.0-22/scripts/extract-vmlinux"

if [ ! -x "$EXTRACTOR" ]; then
  echo "ERROR: extract-vmlinux not found at $EXTRACTOR"
  exit 1
fi

mkdir -p /home/umesh-pc/fc-demo

echo "Extracting ELF kernel from $SOURCE_KERNEL..."
sudo "$EXTRACTOR" "$SOURCE_KERNEL" > "$TARGET_KERNEL"
sudo chown "$USER:$USER" "$TARGET_KERNEL"

if ! file "$TARGET_KERNEL" | grep -q 'ELF'; then
  echo "ERROR: Extracted kernel is not ELF"
  exit 1
fi

echo "✓ Kernel ready: $TARGET_KERNEL"
file "$TARGET_KERNEL"
