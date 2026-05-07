lsmod | grep kvm
ls -l /dev/kvm
egrep -c '(vmx|svm)' /proc/cpuinfo

sudo apt update
sudo apt install -y qemu-kvm curl jq iproute2 iptables

FC_VERSION=v1.9.0
curl -LO https://github.com/firecracker-microvm/firecracker/releases/download/${FC_VERSION}/firecracker-${FC_VERSION}-x86_64
curl -LO https://github.com/firecracker-microvm/firecracker/releases/download/${FC_VERSION}/jailer-${FC_VERSION}-x86_64
sudo mv firecracker-${FC_VERSION}-x86_64 /usr/local/bin/firecracker
sudo mv jailer-${FC_VERSION}-x86_64 /usr/local/bin/jailer
sudo chmod +x /usr/local/bin/firecracker /usr/local/bin/jailer


mkdir -p ~/fc-demo && cd ~/fc-demo

# Example demo images (check docs for current URLs)
curl -LO https://s3.amazonaws.com/spec.ccfc.min/img/hello/kernel/hello-vmlinux.bin
curl -LO https://github.com/firecracker-microvm/firecracker-demo/raw/fea3897ccfab0387ce5cd4fa2dd49d869729d612/xenial.rootfs.ext4



cd ~/fc-demo
rm -f /tmp/firecracker.socket
sudo firecracker --api-sock /tmp/firecracker.socket


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


