#!/bin/bash
set -euo pipefail

ROOTFS="/home/umesh-pc/fc-demo/hello-rootfs.ext4"
MOUNT_DIR="/tmp/firecracker-rootfs.$$"

mkdir -p /home/umesh-pc/fc-demo
rm -f "$ROOTFS"
dd if=/dev/zero of="$ROOTFS" bs=1M count=128 status=none
mkfs.ext4 -F "$ROOTFS" >/dev/null
mkdir -p "$MOUNT_DIR"

cleanup() {
  sudo umount "$MOUNT_DIR" 2>/dev/null || true
  rmdir "$MOUNT_DIR" 2>/dev/null || true
}
trap cleanup EXIT

sudo mount -o loop "$ROOTFS" "$MOUNT_DIR"
sudo mkdir -p "$MOUNT_DIR/bin" "$MOUNT_DIR/dev" "$MOUNT_DIR/proc" "$MOUNT_DIR/sys" "$MOUNT_DIR/tmp" "$MOUNT_DIR/etc"
sudo install -m 0755 /bin/busybox "$MOUNT_DIR/bin/busybox"
sudo ln -sf busybox "$MOUNT_DIR/bin/sh"
sudo ln -sf busybox "$MOUNT_DIR/bin/mount"
sudo ln -sf busybox "$MOUNT_DIR/bin/echo"
sudo ln -sf busybox "$MOUNT_DIR/bin/ls"
sudo ln -sf busybox "$MOUNT_DIR/bin/cat"
sudo ln -sf busybox "$MOUNT_DIR/bin/dmesg"
sudo ln -sf busybox "$MOUNT_DIR/bin/ps"
sudo ln -sf busybox "$MOUNT_DIR/bin/vi"

sudo tee "$MOUNT_DIR/init" >/dev/null <<'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t tmpfs tmpfs /tmp 2>/dev/null || true

echo ""
echo "Firecracker guest booted successfully."
echo ""
echo "Available commands:"
echo "  ls /"
echo "  mount"
echo "  dmesg | tail"
echo ""
exec /bin/sh
EOF
sudo chmod +x "$MOUNT_DIR/init"
sudo sync
sudo umount "$MOUNT_DIR"
rmdir "$MOUNT_DIR"

echo "✓ Rootfs ready: $ROOTFS"
file "$ROOTFS"
