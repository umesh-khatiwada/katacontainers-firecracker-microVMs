set -e

echo "=== Firecracker Setup ==="
echo "1. Checking KVM support..."
lsmod | grep kvm
ls -l /dev/kvm
egrep -c '(vmx|svm)' /proc/cpuinfo

echo ""
echo "2. Installing dependencies..."
sudo apt update -qq
sudo apt install -y qemu-kvm curl jq iproute2 iptables

echo ""
echo "3. Setting up Firecracker binaries..."
FC_VERSION="v1.15.1"
FC_BIN_DIR="$(dirname $(pwd))/release-${FC_VERSION}-x86_64"

# Check for prebuilt binaries in workspace
if [ -f "$FC_BIN_DIR/jailer-${FC_VERSION}-x86_64" ]; then
  sudo cp "$FC_BIN_DIR/jailer-${FC_VERSION}-x86_64" /usr/local/bin/jailer
  sudo chmod +x /usr/local/bin/jailer
  echo "✓ Jailer binary copied from workspace"
else
  echo "⚠ Jailer not found in workspace"
fi

# Download firecracker executable (workspace only has debug version)
echo "Downloading firecracker executable..."
FC_URL="https://github.com/firecracker-microvm/firecracker/releases/download/${FC_VERSION}/firecracker-${FC_VERSION}-x86_64.tgz"
curl -L "$FC_URL" -o /tmp/firecracker.tgz 2>/dev/null
tar -xzf /tmp/firecracker.tgz -C /tmp/
sudo mv /tmp/release-${FC_VERSION}-x86_64/firecracker-${FC_VERSION}-x86_64 /usr/local/bin/firecracker
sudo chmod +x /usr/local/bin/firecracker
rm -rf /tmp/firecracker.tgz /tmp/release-${FC_VERSION}-x86_64
echo "✓ Firecracker binary downloaded, extracted and installed"

# Verify installation
firecracker --version || echo "⚠ Firecracker version check failed"

echo ""
echo "4. Setting up demo environment..."
mkdir -p ~/fc-demo && cd ~/fc-demo

# Download demo images
echo "Downloading demo images..."
curl -L "https://github.com/firecracker-microvm/firecracker/releases/download/v0.32.0/hello-vmlinux.bin" -o hello-vmlinux.bin 2>/dev/null || echo "⚠ Failed to download kernel image"
curl -L "https://github.com/firecracker-microvm/firecracker/releases/download/v0.32.0/xenial.rootfs.ext4" -o xenial.rootfs.ext4 2>/dev/null || echo "⚠ Failed to download rootfs image"

# If downloads failed, use system kernel (note: this is bzImage, may need decompression)
if [ ! -f hello-vmlinux.bin ] || [ $(wc -c < hello-vmlinux.bin) -lt 1000 ]; then
  echo "Creating test environment with system kernel..."
  sudo cp /boot/vmlinuz-$(uname -r) ./hello-vmlinux.bin 2>/dev/null || \
  sudo cp /boot/vmlinuz ./hello-vmlinux.bin 2>/dev/null || \
  echo "Note: Kernel image is bzImage format (compressed) - see QUICKSTART.md for decompression"
  [ -f hello-vmlinux.bin ] && sudo chown $USER:$USER ./hello-vmlinux.bin
fi

# Create minimal rootfs if not downloaded
if [ ! -f xenial.rootfs.ext4 ] || [ $(wc -c < xenial.rootfs.ext4) -lt 1000 ]; then
  echo "Creating minimal ext4 rootfs..."
  dd if=/dev/zero of=xenial.rootfs.ext4 bs=1M count=100 2>/dev/null
  mkfs.ext4 -F xenial.rootfs.ext4 >/dev/null 2>&1
fi

echo ""
echo "5. Firecracker executable installed!"
echo ""
echo "Quick start: cd ~/fc-demo && firecracker --help"
echo ""
echo "NOTE: The API calls below require firecracker to be running."
echo "Start firecracker in one terminal: sudo firecracker --api-sock /tmp/firecracker.socket"
echo "Then run the API calls in another terminal."
echo ""

# These API calls require firecracker to be running first
# Uncomment and run manually after starting firecracker
: <<'API_CALLS'
cd ~/fc-demo
rm -f /tmp/firecracker.socket
sudo firecracker --api-sock /tmp/firecracker.socket &
FIRECRACKER_PID=$!
sleep 2

API=/tmp/firecracker.socket

# Boot source
sudo curl --unix-socket $API -i \
  -X PUT 'http://localhost/boot-source' \
  -H 'Content-Type: application/json' \
  -d "{
    \"kernel_image_path\": \"$(pwd)/hello-vmlinux.bin\",
    \"boot_args\": \"console=ttyS0 reboot=k panic=1 pci=off\"
  }"

# Root drive
sudo curl --unix-socket $API -i \
  -X PUT 'http://localhost/drives/rootfs' \
  -H 'Content-Type: application/json' \
  -d "{
    \"drive_id\": \"rootfs\",
    \"path_on_host\": \"$(pwd)/xenial.rootfs.ext4\",
    \"is_root_device\": true,
    \"is_read_only\": false
  }"

# Start machine
sudo curl --unix-socket $API -i \
  -X PUT 'http://localhost/machine-config' \
  -H 'Content-Type: application/json' \
  -d '{
    \"vcpu_count\": 1,
    \"mem_size_mib\": 256
  }'

sudo curl --unix-socket $API -i \
  -X PUT 'http://localhost/actions' \
  -H 'Content-Type: application/json' \
  -d '{
    \"action_type\": \"InstanceStart\"
  }'

kill $FIRECRACKER_PID
API_CALLS


