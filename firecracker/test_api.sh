#!/bin/bash
# Simple API test - runs without needing sudo password

SOCKET="/tmp/firecracker.socket"
KERNEL="/home/umesh-pc/fc-demo/hello-vmlinux.bin"
ROOTFS="/home/umesh-pc/fc-demo/xenial.rootfs.ext4"

echo "Testing Firecracker API..."
echo ""

# Test 1: Boot source
echo "1. Setting boot source..."
cat << 'EOF' | nc -U "$SOCKET"
PUT /boot-source HTTP/1.1
Content-Type: application/json
Content-Length: 100

{"kernel_image_path": "/home/umesh-pc/fc-demo/hello-vmlinux.bin", "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"}
EOF

sleep 1

echo ""
echo "2. Setting rootfs..."
cat << 'EOF' | nc -U "$SOCKET"
PUT /drives/rootfs HTTP/1.1
Content-Type: application/json
Content-Length: 120

{"drive_id": "rootfs", "path_on_host": "/home/umesh-pc/fc-demo/xenial.rootfs.ext4", "is_root_device": true, "is_read_only": false}
EOF

sleep 1

echo ""
echo "3. Configuring machine..."
cat << 'EOF' | nc -U "$SOCKET"
PUT /machine-config HTTP/1.1
Content-Type: application/json
Content-Length: 40

{"vcpu_count": 2, "mem_size_mib": 512}
EOF

sleep 1

echo ""
echo "4. Starting VM..."
cat << 'EOF' | nc -U "$SOCKET"
PUT /actions HTTP/1.1
Content-Type: application/json
Content-Length: 35

{"action_type": "InstanceStart"}
EOF

echo ""
echo "Done!"
