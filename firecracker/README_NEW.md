# Firecracker Setup & Quick Start Guide

## Status: ✅ Installation Complete

Firecracker v1.15.1 is installed and ready to use!

- **Firecracker executable**: `/usr/local/bin/firecracker`
- **Jailer security tool**: `/usr/local/bin/jailer`
- **Demo VM files**: `~/fc-demo/` (kernel + rootfs)

## Script Layout

- `prepare_kernel.sh` extracts a bootable ELF kernel to `~/fc-demo/vmlinux.bin`
- `prepare_rootfs.sh` builds a minimal BusyBox rootfs with `/init`
- `launch_vm.sh` starts Firecracker and boots the guest
- `script.sh` runs all three steps in order

## ⚠️ Important: Kernel Image Format

**Firecracker requires an uncompressed ELF kernel image.**

Current demo kernel (`~/fc-demo/hello-vmlinux.bin`) is a **bzImage** (compressed), which won't work directly. Firecracker needs an uncompressed ELF kernel, typically named `vmlinux.bin`.

### Fix: Get a Proper Kernel

**Option 1: Download prebuilt minimal kernel (Recommended)**
```bash
cd ~/fc-demo
curl -fL https://s3.amazonaws.com/spec.ccfc.min/img/hello/kernel/hello-vmlinux.bin -o vmlinux.bin
file vmlinux.bin
# Or run ./prepare_kernel.sh to extract one from the host kernel
```

**Option 2: Decompress system kernel**
```bash
cd ~/fc-demo
python3 << 'EOF'
import struct, gzip
with open("hello-vmlinux.bin", "rb") as f:
    data = f.read()
pos = data.find(b'\x1f\x8b\x08')  # gzip magic
if pos > 0:
    kernel = gzip.decompress(data[pos:])
    with open("vmlinux.bin", "wb") as out:
        out.write(kernel)
    print("✓ Decompressed successfully!")
EOF
```

**Option 3: Compile minimal Linux kernel** (Advanced - see kernel build docs)

See [QUICKSTART.md](QUICKSTART.md) for detailed instructions.

---

## Quick Start: 30 Seconds

### Terminal 1: Start Firecracker
```bash
sudo firecracker --api-sock /tmp/firecracker.socket
```

### Terminal 2: Configure & Boot VM
```bash
./script.sh
```

`script.sh` now runs `prepare_kernel.sh`, `prepare_rootfs.sh`, and `launch_vm.sh` in that order.

---

## Files

| File | Purpose |
|------|---------|
| `setup.sh` | Installation script (already run) |
| `prepare_kernel.sh` | Extracts an ELF kernel image |
| `prepare_rootfs.sh` | Builds a bootable BusyBox ext4 rootfs |
| `launch_vm.sh` | Boots Firecracker with the prepared artifacts |
| `script.sh` | Runs the full workflow end-to-end |
| `test.sh` | Simple API test |
| `QUICKSTART.md` | **→ Detailed step-by-step guide** |
| `README_NEW.md` | This file |

## Architecture

Firecracker manages lightweight VMs via REST API:

```
Firecracker (Hypervisor)
    ↓ REST API (unix socket)
┌─────────────────────┐
│ Linux microVM       │
│ - Kernel            │
│ - Rootfs            │
│ - 1-8 vCPUs         │
│ - 128-16GB RAM      │
└─────────────────────┘
```

## API Endpoints

All requests go to `http://localhost/{path}` via `/tmp/firecracker.socket`

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/machine-config` | PUT | vCPU count, memory size |
| `/boot-source` | PUT | Kernel image, boot args |
| `/drives/{id}` | PUT | Attach block devices |
| `/net-ifaces` | PUT | Network interfaces |
| `/actions` | PUT | Start, pause, kill VM |

## Troubleshooting

| Error | Solution |
|-------|----------|
| "Invalid Elf magic number" | Run `./prepare_kernel.sh` to generate `vmlinux.bin` |
| "Socket already in use" | `sudo lsof /tmp/firecracker.socket && sudo kill -9 <PID>` |
| "Permission denied" | Use `sudo` with curl commands |
| "No working init found" | Run `./prepare_rootfs.sh` to build the BusyBox rootfs |

## See Also

- [QUICKSTART.md](QUICKSTART.md) - Detailed step-by-step guide
- [Firecracker Docs](https://github.com/firecracker-microvm/firecracker)
- Parent directory - Kata Containers integration
