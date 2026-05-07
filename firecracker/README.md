firecracker
domain: https://firecracker-microvm.github.io/



# Firecracker on a Linux VPS

This guide documents the exact process used to install and run Firecracker on a Linux VPS with KVM support.

The path below assumes:

- Host architecture: `x86_64`
- Running as `root` or with `sudo`
- Firecracker repo available at `/root/firecracker`
- Demo root filesystem available at `/root/fc-demo/hello-rootfs.ext4`
- Guest kernel available at `/root/firecracker/vmlinux-6.1.155`

## 1. Prerequisites

Firecracker needs hardware virtualization via KVM.

Check that the VPS exposes KVM:

```bash
ls -l /dev/kvm
grep -m1 -E 'vmx|svm' /proc/cpuinfo
```

If `/dev/kvm` is missing, Firecracker cannot run on that VPS.

Install the utilities used by the launch flow:

```bash
apt-get update
apt-get install -y curl jq iptables iproute2 openssh-client e2fsprogs util-linux kmod
```

Optional but useful:

```bash
apt-get install -y usbutils
```
```
git clone https://github.com/firecracker-microvm/firecracker
cd firecracker
tools/devtool build
toolchain="$(uname -m)-unknown-linux-musl"
```


## 2. Verify the Firecracker build

The repository already contains a working build in:

```bash
/root/firecracker/build/cargo_target/x86_64-unknown-linux-musl/debug/firecracker
```

If you need to rebuild it from source, use:

```bash
cd /root/firecracker
sudo ./tools/devtool build
```

## 3. Prepare the guest kernel and rootfs

The working guest kernel used here is:

```bash
/root/firecracker/vmlinux-6.1.155
```

The working rootfs used here is:

```bash
/root/fc-demo/hello-rootfs.ext4
```

Confirm the rootfs is a valid ext4 image:

```bash
file /root/fc-demo/hello-rootfs.ext4
e2fsck -fn /root/fc-demo/hello-rootfs.ext4
```

## 4. Start Firecracker

Open one terminal and start the VMM:

```bash
cd /root/firecracker
rm -f /tmp/firecracker.socket /tmp/firecracker.log
./build/cargo_target/x86_64-unknown-linux-musl/debug/firecracker \
  --api-sock /tmp/firecracker.socket \
  --log-path /tmp/firecracker.log \
  --level Info
```

Keep this terminal open.

## 5. Boot the microVM

In a second terminal, send the boot configuration:

```bash
API_SOCKET=/tmp/firecracker.socket
KERNEL=/root/firecracker/vmlinux-6.1.155
ROOTFS=/root/fc-demo/hello-rootfs.ext4

curl -X PUT --unix-socket "$API_SOCKET" \
  -H 'Content-Type: application/json' \
  --data "{\"kernel_image_path\":\"$KERNEL\",\"boot_args\":\"console=ttyS0 reboot=k panic=1\"}" \
  http://localhost/boot-source

curl -X PUT --unix-socket "$API_SOCKET" \
  -H 'Content-Type: application/json' \
  --data "{\"drive_id\":\"rootfs\",\"path_on_host\":\"$ROOTFS\",\"is_root_device\":true,\"is_read_only\":false}" \
  http://localhost/drives/rootfs

curl -X PUT --unix-socket "$API_SOCKET" \
  -H 'Content-Type: application/json' \
  --data '{"action_type":"InstanceStart"}' \
  http://localhost/actions
```

If the boot succeeds, the guest will reach a serial console login prompt in the Firecracker terminal.

## 6. What success looks like

The guest should print kernel boot messages and eventually show something like:

```text
localhost login:
```

That means Firecracker is running and the guest has booted successfully.

## 7. Optional networking

The demo above boots the guest without networking. If you want SSH access, create and attach a TAP device, then add a network interface before `InstanceStart`.

Example host setup:

```bash
TAP_DEV=tap0
TAP_IP=172.16.0.1
MASK_SHORT=/30

ip link del "$TAP_DEV" 2>/dev/null || true
ip tuntap add dev "$TAP_DEV" mode tap
ip addr add "${TAP_IP}${MASK_SHORT}" dev "$TAP_DEV"
ip link set dev "$TAP_DEV" up

echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -P FORWARD ACCEPT

HOST_IFACE=$(ip -j route list default | jq -r '.[0].dev')
iptables -t nat -D POSTROUTING -o "$HOST_IFACE" -j MASQUERADE 2>/dev/null || true
iptables -t nat -A POSTROUTING -o "$HOST_IFACE" -j MASQUERADE
```

Then attach the network interface via the API:

```bash
curl -X PUT --unix-socket "$API_SOCKET" \
  -H 'Content-Type: application/json' \
  --data '{"iface_id":"net1","guest_mac":"06:00:AC:10:00:02","host_dev_name":"tap0"}' \
  http://localhost/network-interfaces/net1
```

After boot, the guest can be reached at `172.16.0.2`.

## 8. Guest networking commands

Inside the guest, set the default route and DNS:

```bash
ip route add default via 172.16.0.1 dev eth0
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
```

Then SSH in:

```bash
ssh root@172.16.0.2
```

## 9. Shutdown

From inside the guest, run:

```bash
reboot
```

Firecracker exits cleanly when the guest reboots.

## 10. Troubleshooting

- If Firecracker fails to start, check `/tmp/firecracker.log`.
- If the guest does not boot, confirm the kernel path and rootfs path are correct.
- If `/dev/kvm` is missing, the VPS provider may not expose virtualization support.
- If networking fails, confirm the TAP interface exists and `iptables` NAT is configured.
