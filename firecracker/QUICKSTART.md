# Firecracker Setup & Testing Guide

## Status: ✅ Installation Complete

Firecracker v1.15.1 is successfully installed at `/usr/local/bin/firecracker`

## Script Layout

- `prepare_kernel.sh` extracts the host kernel into an ELF `vmlinux.bin`
- `prepare_rootfs.sh` builds a BusyBox-based ext4 rootfs with `/init`
- `launch_vm.sh` starts Firecracker and configures the VM
- `script.sh` runs kernel prep, rootfs prep, and launch in order

## ⚠️ Important: Kernel Image Format

The demo currently uses a **bzImage** (compressed kernel) located at `/home/umesh-pc/fc-demo/hello-vmlinux.bin`.

**Issue**: Firecracker requires an **uncompressed ELF kernel image**, not a bzImage.

### Getting a Proper Kernel Image

Choose one of these options:

#### Option 1: Use a Prebuilt Firecracker Test Kernel (Recommended)
```bash
# Download Ubuntu's Firecracker test kernel
cd ~/fc-demo
curl -fL https://s3.amazonaws.com/spec.ccfc.min/img/hello/kernel/hello-vmlinux.bin -o vmlinux.bin
file vmlinux.bin

# Or use this alternative minimal kernel
curl -fL https://cloud-images.ubuntu.com/fakes/gzipped-vmlinux-4.14.176 -o vmlinux.bin
file vmlinux.bin
```

#### Option 2: Decompress System Kernel
```bash
cd ~/fc-demo

# Try to extract and decompress the system kernel
python3 << 'EOF'
import struct, gzip

# Read bzImage
with open("hello-vmlinux.bin", "rb") as f:
    data = f.read()

# Find gzip compression inside bzImage (typically after setup code)
pos = data.find(b'\x1f\x8b\x08')  # gzip magic number
if pos > 0:
    try:
        kernel = gzip.decompress(data[pos:])
        with open("vmlinux-decompressed.bin", "wb") as out:
            out.write(kernel)
        print(f"✓ Decompressed {len(kernel)} bytes")
    except:
        print("Failed to decompress - kernel format may be complex")
else:
    print("No gzip data found in kernel")
EOF

# If successful, use it in launch_vm.sh or the wrapper script.sh
```

#### Option 3: Compile Minimal Kernel
```bash
# This requires: build-essential, flex, bison, libelf-dev
# See kernel compilation guides for your distro
```

## Running Firecracker

### Step 1: Start Firecracker with API Socket

In **Terminal 1**, run:
```bash
sudo rm -f /tmp/firecracker.socket
sudo firecracker --api-sock /tmp/firecracker.socket
```

You'll see:
```
Running Firecracker v1.15.1
```

### Step 2: Configure VM via API

In **Terminal 2**, once you have a proper uncompressed kernel and a prepared rootfs, run:

#### 2.1 Run the full workflow
```bash
./script.sh
```

`launch_vm.sh` sends the API calls in the correct order and adds `init=/init` so the BusyBox guest shell starts cleanly.

## Files
- **Kernel**: `/home/umesh-pc/fc-demo/hello-vmlinux.bin` (16M - Linux kernel)
- **Rootfs**: `/home/umesh-pc/fc-demo/hello-rootfs.ext4` (128M - BusyBox ext4 filesystem)
- **Firecracker**: `/usr/local/bin/firecracker` (executable)
- **Jailer**: `/usr/local/bin/jailer` (security jail)

## Troubleshooting

### Socket already in use
```bash
sudo lsof /tmp/firecracker.socket
sudo kill -9 <PID>
```

### Permission denied
Make sure you run curl commands with `sudo`

### API returns 400 errors
Check that paths are absolute (not relative) and files exist:
```bash
ls -lh /home/umesh-pc/fc-demo/
```

## Files in Workspace
- `prepare_kernel.sh` - Extracts a bootable ELF kernel from the host
- `prepare_rootfs.sh` - Builds a minimal BusyBox rootfs with `/init`
- `launch_vm.sh` - Boots Firecracker and starts the guest
- `script.sh` - Wrapper that runs all three steps
- `test.sh` - API smoke test against a prepared VM
- `README.md` - Documentation
