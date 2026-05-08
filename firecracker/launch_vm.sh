#!/bin/bash
API="/tmp/firecracker.socket"
FC_DEMO_DIR="/home/umesh-pc/fc-demo"

echo "1. Configuring boot source..."
sudo curl --unix-socket $API -i \
  -X PUT 'http://localhost/boot-source' \
  -H 'Content-Type: application/json' \
  -d "{
    \"kernel_image_path\": \"$FC_DEMO_DIR/vmlinux.bin\",
    \"boot_args\": \"console=ttyS0 reboot=k panic=1 pci=off\"
  }"

echo -e "\n2. Configuring root drive..."
sudo curl --unix-socket $API -i \
  -X PUT 'http://localhost/drives/rootfs' \
  -H 'Content-Type: application/json' \
  -d "{
    \"drive_id\": \"rootfs\",
    \"path_on_host\": \"$FC_DEMO_DIR/hello-rootfs.ext4\",
    \"is_root_device\": true,
    \"is_read_only\": false
  }"

echo -e "\n3. Starting microVM..."
sudo curl --unix-socket $API -i \
  -X PUT 'http://localhost/actions' \
  -H 'Content-Type: application/json' \
  -d '{
    "action_type": "InstanceStart"
  }'
