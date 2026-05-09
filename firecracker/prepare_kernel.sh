#!/bin/bash
set -euo pipefail

SOURCE_KERNEL="/boot/vmlinuz-$(uname -r)"
TARGET_KERNEL="/home/umesh-pc/fc-demo/vmlinux.bin"

mkdir -p /home/umesh-pc/fc-demo

# Try to find extract-vmlinux in several places
EXTRACTOR=""
for candidate in \
  /usr/src/linux-headers-$(uname -r)/scripts/extract-vmlinux \
  /usr/src/linux-hwe-*-headers-*/scripts/extract-vmlinux \
  /usr/local/bin/extract-vmlinux \
  $(which extract-vmlinux 2>/dev/null || true); do
  if [ -x "$candidate" ]; then
    EXTRACTOR="$candidate"
    break
  fi
done

# If still not found, download it directly from kernel.org
if [ -z "$EXTRACTOR" ]; then
  echo "extract-vmlinux not found locally — downloading from kernel.org..."
  KERNEL_VERSION=$(uname -r | grep -oP '^\d+\.\d+')
  wget -q -O /usr/local/bin/extract-vmlinux \
    "https://raw.githubusercontent.com/torvalds/linux/v${KERNEL_VERSION}/scripts/extract-vmlinux"
  chmod +x /usr/local/bin/extract-vmlinux
  EXTRACTOR="/usr/local/bin/extract-vmlinux"
fi

echo "Using extractor: $EXTRACTOR"
echo "Extracting ELF kernel from $SOURCE_KERNEL..."
sudo "$EXTRACTOR" "$SOURCE_KERNEL" > "$TARGET_KERNEL"
sudo chown "$USER:$USER" "$TARGET_KERNEL"

if ! file "$TARGET_KERNEL" | grep -q 'ELF'; then
  echo "ERROR: Extracted kernel is not ELF"
  exit 1
fi

echo "✓ Kernel ready: $TARGET_KERNEL"
file "$TARGET_KERNEL"