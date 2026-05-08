#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

"$DIR/prepare_kernel.sh"
"$DIR/prepare_rootfs.sh"
"$DIR/launch_vm.sh"
