# Kata Containers, Firecracker microVMs and gVisor Experiments

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Shell](https://img.shields.io/badge/shell-bash-green)
![Python](https://img.shields.io/badge/python-3-blue)

Hands-on notes and scripts for exploring sandboxed / lightweight-VM isolation technologies: **Firecracker microVMs**, **gVisor** and (as a placeholder) **Kata Containers**.

## Overview

| Directory | What it contains |
|---|---|
| [`firecracker/`](firecracker/) | Step-by-step guides and helper scripts to install Firecracker v1.15.1 on a KVM-capable Linux host, build a demo kernel and BusyBox rootfs, and boot a microVM through the Firecracker API socket. |
| [`gvisior/`](gvisior/) | A parallel PDF-generation demo: a FastAPI service enqueues jobs on RabbitMQ, N workers render HTML to PDF with WeasyPrint. Workers run on plain Docker or under gVisor (`runsc`). |
| [`katacontainers/`](katacontainers/) | Placeholder only (links to https://katacontainers.io). |
| [`release-v1.15.1-x86_64/`](release-v1.15.1-x86_64/) | Vendored upstream Firecracker v1.15.1 release artifacts (binaries, CPU templates, seccomp filters, API spec). Licensed by upstream under Apache-2.0, see the `LICENSE` and `NOTICE` files in that folder. |

## Prerequisites

- Firecracker demo: Linux x86_64 with KVM (`/dev/kvm`), `curl`, `jq`, `iproute2`, `iptables`, `e2fsprogs`, root/sudo.
- gVisor demo: Docker with Compose; Python 3 (standard library only) for the load test. gVisor sandboxing itself requires a Linux host with `runsc` installed (https://gvisor.dev/docs/user_guide/install/).

## Quick start: Firecracker

Check KVM support first:

```bash
ls -l /dev/kvm
grep -m1 -E 'vmx|svm' /proc/cpuinfo
```

Then either follow the manual walkthrough in [`firecracker/README.md`](firecracker/README.md) (start the VMM, then `PUT` to `/boot-source`, `/drives/rootfs` and `/actions` on the API socket), or use the helper scripts:

```bash
cd firecracker
./script.sh   # runs prepare_kernel.sh -> prepare_rootfs.sh -> launch_vm.sh
```

> Note: the scripts currently hardcode paths such as `/home/umesh-pc/fc-demo` and expect the `firecracker` binary at `/usr/local/bin/firecracker`. Edit them for your environment (TODO: parameterise).

Helper scripts in `firecracker/`:

| Script | Purpose |
|---|---|
| `setup.sh` | Check KVM and install dependencies (apt) |
| `prepare_kernel.sh` | Extract an uncompressed ELF `vmlinux.bin` from the host kernel |
| `prepare_rootfs.sh` | Build a minimal BusyBox ext4 rootfs |
| `launch_vm.sh` | Configure and start the microVM via the API socket |
| `test.sh`, `test_api.sh`, `diagnose.sh` | Exercise/diagnose the Firecracker API step by step |
| `fixes.sh` | Notes for adding your user to the `kvm` group |

Important: Firecracker needs an **uncompressed ELF kernel** (not a bzImage); see [`firecracker/QUICKSTART.md`](firecracker/QUICKSTART.md).

## Quick start: gVisor + RabbitMQ PDF demo

```bash
cd gvisior
docker compose up --build -d --scale worker=10
N=100 python3 scripts/load_test.py
```

- API docs: http://localhost:8000/docs
- RabbitMQ management UI: http://localhost:15672 (default local-demo guest account)

API endpoints (from `gvisior/api/app.py`): `POST /pdf`, `GET /pdf/{job_id}`, `GET /download/{job_id}`, `GET /health`.

```bash
curl -s -X POST http://localhost:8000/pdf -H 'Content-Type: application/json' \
  -d '{"html":"<h1>Hello gVisor</h1>"}'
```

To run workers under gVisor, layer the override file: `docker compose -f docker-compose.yml -f docker-compose.gvisor.yml up --build -d --scale worker=10`. A managed-broker variant (`docker-compose.cloudamqp.yml`) is also provided. Details, troubleshooting and the measured results are in [`gvisior/README.md`](gvisior/README.md) and [`gvisior/IMPLEMENTATION_PLAN.md`](gvisior/IMPLEMENTATION_PLAN.md).

### Configuration

| Variable | Used by | Default | Description |
|---|---|---|---|
| `RABBITMQ_URL` | api, worker | local `rabbitmq` container | AMQP connection URL. Put a real URL only in a git-ignored `.env`. |
| `PDF_QUEUE` | api, worker | `pdf_jobs` | Queue name |
| `STORAGE_DIR` | api, worker | `/data` | Shared volume for generated PDFs |

`gvisior/.env.example` also lists `MINIO_*` variables, but the current API/worker code does not read them (TODO: reconcile).

## Project structure

```text
.
├── firecracker/          # install guides + helper scripts
├── gvisior/              # API, worker, compose files, load test
├── katacontainers/       # placeholder
└── release-v1.15.1-x86_64/  # vendored upstream Firecracker release
```

## Roadmap

- Parameterise hardcoded paths in the Firecracker scripts.
- Consolidate the overlapping Firecracker docs (`README.md`, `README_NEW.md`, `QUICKSTART.md`).
- Add actual Kata Containers content.

## License

This repository's own content is released under the [MIT License](LICENSE). The vendored files in `release-v1.15.1-x86_64/` remain under their upstream license (Apache-2.0).

## Author

Umesh Khatiwada, https://github.com/umesh-khatiwada
