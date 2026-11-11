# gVisor + RabbitMQ Parallel PDF Generation — Implementation Plan

A beginner-friendly plan for generating many PDFs in parallel using **isolated gVisor
sandboxes** that consume jobs from a **RabbitMQ** queue.

---

## 1. The problem we are solving

> "100 users ask for a PDF at the same time. If I process them one-by-one through a
> queue, it takes forever. I want multiple isolated sandboxes pulling jobs off the queue
> and generating PDFs in parallel."

Two independent concerns:

1. **Throughput** — process many PDFs at once instead of sequentially → solved by the
   *competing consumers* pattern on a message queue.
2. **Security** — PDF generators parse untrusted user HTML/fonts/images (a large attack
   surface) → solved by running each worker inside a **gVisor sandbox**.

---

## 2. What is gVisor (in one picture)

```
Plain container:   App ──syscall──────────────▶ Host Linux Kernel      (thin isolation)

gVisor container:  App ──syscall──▶ Sentry (user-space kernel in Go) ──▶ few filtered syscalls
                                     ▲ intercepts & handles syscalls itself
```

- `runsc` is gVisor's **OCI runtime** — a drop-in replacement for Docker's default `runc`.
- You opt in per container: `docker run --runtime=runsc ...` or `runtime: runsc` in compose.
- Benefit: VM-grade isolation, far lighter/faster to boot than a real VM.
- Cost: some overhead on syscall-heavy I/O.

**Platform note:** `runsc` is **Linux-only**. On an Apple-Silicon Mac you develop with
plain Docker first, then run the same images under `runsc` inside a Linux VM (Colima/Lima)
or a cloud Linux box.

---

## 3. Target architecture

```
                                            ┌─▶ Worker 1 (runsc) ─┐
  Clients ─▶ API (FastAPI) ─▶ [ RabbitMQ ] ─┼─▶ Worker 2 (runsc) ─┼─▶ MinIO (S3 storage)
   POST /pdf     publish job   queue:        ├─▶ Worker 3 (runsc) ─┤      key = <job_id>.pdf
   GET  /pdf/{id}              pdf_jobs      └─▶ Worker N (runsc) ─┘
```

**Flow**
1. Client `POST /pdf` with HTML → API mints a `job_id`, publishes a *persistent* message to
   the `pdf_jobs` queue, returns `{job_id, status: "queued"}` immediately (non-blocking).
2. Each worker has `prefetch=1` → RabbitMQ hands one job to exactly one idle worker.
3. Worker renders HTML→PDF (WeasyPrint), uploads to MinIO as `<job_id>.pdf`, then **acks**.
4. Client polls `GET /pdf/{job_id}` → once the object exists, API returns a presigned
   download URL.

**Why this is fast:** with N workers you process ~N PDFs concurrently. Throughput scales by
just adding workers (`docker compose up --scale worker=10`).

**Why it's reliable:** messages are persistent and only acked *after* a successful upload.
If a worker crashes mid-job, RabbitMQ redelivers the un-acked message to another worker.

---

## 4. Components

| Component | Tech | Role |
|---|---|---|
| API | FastAPI + pika | Accept requests, publish jobs, serve download URLs |
| Queue | RabbitMQ (management image) | Buffer + distribute jobs, redeliver on failure |
| Worker | pika + WeasyPrint | Consume job, render PDF, write result |
| Storage | shared Docker volume (`pdf_data`) | Store generated PDFs; API streams them via `/download/{id}` |
| Load test | stdlib urllib + threads | Fire N jobs and measure wall-clock time |

No database needed for the demo: job status = "does `<job_id>.pdf` exist in the shared
volume yet?".

> **Storage note:** this demo uses a shared Docker volume because it needs zero external
> images. In production, swap it for a real object store (S3 / MinIO) and return a
> presigned URL — the worker/API code changes in only one place (where it writes/reads
> the PDF).

---

## 5. Phased plan

### Phase 0 — Prereqs
- Docker Desktop on your Mac. That's all you need for Phases 1–3.

### Phase 1 — Pipeline on plain Docker (learn the moving parts)
- `docker compose up --build`
- Services: rabbitmq, minio, api, worker.
- Verify: open RabbitMQ UI (http://localhost:15672, guest/guest) and MinIO console
  (http://localhost:9001, minioadmin/minioadmin).
- Submit one job with curl, poll for the download URL. ✅ End-to-end works.

### Phase 2 — Prove parallelism
- `docker compose up --scale worker=1` → run `scripts/load_test.py` (100 jobs) → note time.
- `docker compose up --scale worker=10` → run it again → note the big drop in wall-clock.
- Watch the queue depth spike and drain in the RabbitMQ UI.

### Phase 3 — Harden (optional, still plain Docker)
- Dead-letter queue for jobs that fail repeatedly (poison messages).
- Resource limits per worker (`cpus`, `mem_limit`).
- Timeout around rendering so a hostile document can't hang a worker forever.

### Phase 4 — Switch workers to gVisor (on Linux)
- Provision Linux: `colima start` (Mac) **or** a cloud Ubuntu VM.
- Install gVisor: follow https://gvisor.dev/docs/user_guide/install/ (adds the `runsc`
  Docker runtime).
- In `docker-compose.yml`, uncomment `runtime: runsc` under the `worker` service.
- `docker compose up --build --scale worker=10`. Same behaviour — now each worker is
  sandboxed. Confirm with `docker exec <worker> dmesg` (gVisor shows its own fake kernel).

### Phase 5 — Production notes (future)
- Real object store (AWS S3), managed RabbitMQ (or Amazon MQ), autoscaling worker pool
  (Kubernetes with the gVisor `RuntimeClass`, or a queue-length-based autoscaler).
- Push notifications (webhook / websocket) instead of polling.
- Authentication on the API, signed/expiring download URLs.

---

## 6. How to measure success

- **Correctness:** every submitted job produces a downloadable PDF.
- **Parallelism:** 100 jobs with 10 workers finish in roughly 1/10th the single-worker time.
- **Resilience:** `docker kill` a worker mid-run → its in-flight job is redelivered and still
  completes.
- **Isolation (Phase 4):** worker runs under `runsc`; a crash/exploit inside cannot touch the
  host kernel.

---

## 7. File layout (created in this repo)

```
gvisior/
├── IMPLEMENTATION_PLAN.md   ← this file
├── README.md                ← step-by-step run guide
├── docker-compose.yml       ← all services; gVisor toggle is one commented line
├── .env.example             ← configuration defaults
├── api/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app.py               ← FastAPI: publish jobs, serve download URLs
├── worker/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── worker.py            ← consume jobs, render PDF, upload to MinIO
└── scripts/
    └── load_test.py         ← fire 100 concurrent jobs, measure time
```
