# 1. Start firecracker with an API socket
sudo firecracker --api-sock /tmp/firecracker.socket

# 2. Configure boot source (kernel + boot args)
sudo curl --unix-socket /tmp/firecracker.socket -i \
  -X PUT 'http://localhost/boot-source' \
  -H 'Content-Type: application/json' \
  -d '{
    "kernel_image_path": "./vmlinux.bin",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"
  }'

# 3. Attach root block device
sudo curl --unix-socket /tmp/firecracker.socket -i \
  -X PUT 'http://localhost/drives/rootfs' \
  -H 'Content-Type: application/json' \
  -d '{
    "drive_id": "rootfs",
    "path_on_host": "./rootfs.ext4",
    "is_root_device": true,
    "is_read_only": false
  }'

# 4. Start the guest
sudo curl --unix-socket /tmp/firecracker.socket -i \
  -X PUT 'http://localhost/actions' \
  -H 'Content-Type: application/json' \
  -d '{ "action_type": "InstanceStart" }'