#!/bin/bash
# Diagnostic script to test Firecracker API step-by-step

SOCKET="/tmp/firecracker.socket"
KERNEL="/home/umesh-pc/fc-demo/vmlinux.bin"
ROOTFS="/home/umesh-pc/fc-demo/hello-rootfs.ext4"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "═══════════════════════════════════════════════════════════════"
echo "Firecracker API Diagnostic Test"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check if firecracker is running
if [ ! -S "$SOCKET" ]; then
  echo -e "${RED}✗ ERROR: Socket not found at $SOCKET${NC}"
  echo "  Start firecracker first: sudo firecracker --api-sock $SOCKET"
  exit 1
fi

echo -e "${GREEN}✓${NC} Firecracker socket found"
echo ""

# Check kernel file
if [ ! -f "$KERNEL" ]; then
  echo -e "${RED}✗ ERROR: Kernel file not found${NC}"
  echo "  Path: $KERNEL"
  exit 1
fi
echo -e "${GREEN}✓${NC} Kernel file found"
echo "  File: $(file $KERNEL | cut -d: -f2-)"
echo "  Size: $(ls -lh $KERNEL | awk '{print $5}')"
echo ""

# Check rootfs file
if [ ! -f "$ROOTFS" ]; then
  echo -e "${RED}✗ ERROR: Rootfs file not found${NC}"
  echo "  Path: $ROOTFS"
  exit 1
fi
echo -e "${GREEN}✓${NC} Rootfs file found"
echo "  Size: $(ls -lh $ROOTFS | awk '{print $5}')"
echo ""

echo "───────────────────────────────────────────────────────────────"
echo "API Calls (in order):"
echo "───────────────────────────────────────────────────────────────"
echo ""

# 1. Machine config
echo "1. Setting machine config..."
RESPONSE=$(sudo curl -s --unix-socket "$SOCKET" -w "\n%{http_code}" \
  -X PUT 'http://localhost/machine-config' \
  -H 'Content-Type: application/json' \
  -d '{"vcpu_count": 1, "mem_size_mib": 256, "smt": false}')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "204" ]; then
  echo -e "${GREEN}✓${NC} Machine config set (HTTP 204)"
else
  echo -e "${RED}✗${NC} Machine config failed (HTTP $HTTP_CODE)"
  echo "  Response: $BODY"
fi
echo ""

sleep 1

# 2. Boot source
echo "2. Setting boot source..."
RESPONSE=$(sudo curl -s --unix-socket "$SOCKET" -w "\n%{http_code}" \
  -X PUT 'http://localhost/boot-source' \
  -H 'Content-Type: application/json' \
  -d "{\"kernel_image_path\": \"$KERNEL\", \"boot_args\": \"console=ttyS0 reboot=k panic=1 pci=off\"}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "204" ]; then
  echo -e "${GREEN}✓${NC} Boot source set (HTTP 204)"
else
  echo -e "${RED}✗${NC} Boot source failed (HTTP $HTTP_CODE)"
  echo "  Response: $BODY"
  echo ""
  echo "  Kernel path: $KERNEL"
  echo "  File exists: $([ -f $KERNEL ] && echo 'YES' || echo 'NO')"
  echo "  File type: $(file $KERNEL | cut -d: -f2-)"
fi
echo ""

sleep 1

# 3. Rootfs
echo "3. Attaching rootfs..."
RESPONSE=$(sudo curl -s --unix-socket "$SOCKET" -w "\n%{http_code}" \
  -X PUT 'http://localhost/drives/rootfs' \
  -H 'Content-Type: application/json' \
  -d "{\"drive_id\": \"rootfs\", \"path_on_host\": \"$ROOTFS\", \"is_root_device\": true, \"is_read_only\": false}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "204" ]; then
  echo -e "${GREEN}✓${NC} Rootfs attached (HTTP 204)"
else
  echo -e "${RED}✗${NC} Rootfs attachment failed (HTTP $HTTP_CODE)"
  echo "  Response: $BODY"
fi
echo ""

sleep 1

# 4. Start VM
echo "4. Starting microVM..."
RESPONSE=$(sudo curl -s --unix-socket "$SOCKET" -w "\n%{http_code}" \
  -X PUT 'http://localhost/actions' \
  -H 'Content-Type: application/json' \
  -d '{"action_type": "InstanceStart"}')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "204" ]; then
  echo -e "${GREEN}✓${NC} VM started (HTTP 204)"
  echo ""
  echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}SUCCESS! Check Terminal 1 for kernel boot output.${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
else
  echo -e "${RED}✗${NC} VM start failed (HTTP $HTTP_CODE)"
  echo "  Response: $BODY"
  echo ""
  echo "  Troubleshooting:"
  echo "  - Check that boot-source was successfully set (HTTP 204 above)"
  echo "  - Verify kernel file format: $(file $KERNEL | cut -d: -f2-)"
  echo "  - Kernel file must be uncompressed ELF, not bzImage"
fi
echo ""
