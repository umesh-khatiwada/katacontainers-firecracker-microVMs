#!/bin/bash
# Simplified test script for Firecracker API

SOCKET="/tmp/firecracker.socket"

# Assumes firecracker is already running in another terminal:
# sudo firecracker --api-sock /tmp/firecracker.socket

echo "Testing Firecracker API Configuration..."
echo ""

# Machine config
echo "1. Setting machine config (1 vCPU, 256 MB RAM)..."
sudo curl --unix-socket "$SOCKET" -i \
  -X PUT 'http://localhost/machine-config' \
  -H 'Content-Type: application/json' \
  -d '{"vcpu_count": 1, "mem_size_mib": 256, "smt": false}' \
  2>/dev/null | head -1

# Boot source - requires an ELF vmlinux.bin
echo "2. Setting boot source..."
sudo curl --unix-socket "$SOCKET" -i \
  -X PUT 'http://localhost/boot-source' \
  -H 'Content-Type: application/json' \
  -d '{"kernel_image_path": "/home/umesh-pc/fc-demo/vmlinux.bin", "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"}' \
  2>/dev/null | head -1

sleep 1

# Rootfs  
echo "3. Attaching rootfs..."
sudo curl --unix-socket "$SOCKET" -i \
  -X PUT 'http://localhost/drives/rootfs' \
  -H 'Content-Type: application/json' \
  -d '{"drive_id": "rootfs", "path_on_host": "/home/umesh-pc/fc-demo/hello-rootfs.ext4", "is_root_device": true, "is_read_only": false}' \
  2>/dev/null | head -1

sleep 1

# Start VM
echo "4. Starting VM..."
sudo curl --unix-socket "$SOCKET" -i \
  -X PUT 'http://localhost/actions' \
  -H 'Content-Type: application/json' \
  -d '{"action_type": "InstanceStart"}' \
  2>/dev/null | head -5

echo ""
echo "Done! Check Terminal 1 (firecracker) for boot output."
