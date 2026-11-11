# Parallel PDF Generation with gVisor + RabbitMQ

A beginner demo: an API drops PDF jobs on **RabbitMQ**; many **worker** sandboxes consume
them in parallel, render HTML→PDF (WeasyPrint), and write results to a **shared volume**.
Workers run on plain Docker now and under **gVisor (`runsc`)** on Linux with a one-line change.

See **[IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)** for the concepts and architecture.

```
Clients ─▶ API ─▶ [RabbitMQ: pdf_jobs] ─▶ Worker × N ─▶ shared volume (<job_id>.pdf)
POST /pdf        publish job             prefetch=1           served by API /download/{id}
GET  /pdf/{id}   poll status
```

## Two ways to run

| File | Broker | Use |
|---|---|---|
| `docker-compose.yml` | local RabbitMQ container | fully self-contained, no account needed |
| `docker-compose.cloudamqp.yml` | your managed CloudAMQP | realistic, `RABBITMQ_URL` from `.env` |

## Prerequisites
- Docker Desktop (macOS is fine for everything except the actual gVisor sandbox).
- Python 3 on your host for the load test (standard library only — no pip install).

## A) Self-contained run (local RabbitMQ)

```bash
docker compose up --build -d --scale worker=10
N=100 python3 scripts/load_test.py
```
- API docs:    http://localhost:8000/docs
- RabbitMQ UI: http://localhost:15672  (guest / guest)

## B) Managed broker run (CloudAMQP) — what we tested

```bash
# .env (git-ignored) holds the secret:
echo 'RABBITMQ_URL=amqps://USER:PASS@HOST/VHOST' > .env

docker compose -f docker-compose.cloudamqp.yml up --build -d --scale worker=20
N=200 CONCURRENCY=100 python3 scripts/load_test.py
```

**Measured result (20 workers, 200 requests):**
```
Submitted 200 jobs in 0.35s (100 concurrent)   <- API is non-blocking
... 200/200 done ...
ALL 200 PDFs ready in 20.85s                    <- ~10-12 jobs per worker, 0 failures
```

## Submit one job by hand
```bash
curl -s -X POST http://localhost:8000/pdf -H 'Content-Type: application/json' \
  -d '{"html":"<h1>Hello gVisor</h1>"}'
# -> {"job_id":"<id>","status":"queued"}
curl -s http://localhost:8000/pdf/<id>          # -> status + download_url when ready
```

## Prove parallelism
Run the load test with `--scale worker=1`, note the time, then `--scale worker=20` and
watch wall-clock drop roughly N×. Watch the queue spike and drain in the RabbitMQ UI.

## Test resilience
While a run is in flight, `docker kill` a worker. Its un-acked job is redelivered to
another worker and still completes (we ack only after the file is written).

## Enable gVisor (Linux only)
1. Linux host: `colima start` on Mac, or a cloud Ubuntu VM.
2. Install gVisor (adds the `runsc` runtime): https://gvisor.dev/docs/user_guide/install/
3. Start with the matching gVisor override file:
   ```bash
   # local RabbitMQ
   docker compose -f docker-compose.yml -f docker-compose.gvisor.yml up --build -d --scale worker=10
   # CloudAMQP
   docker compose -f docker-compose.cloudamqp.yml -f docker-compose.cloudamqp.gvisor.yml up --build -d --scale worker=20
   ```
4. Same behaviour — now every worker is a sandbox. Check with
   `docker exec <worker> cat /proc/version` (shows `4.19.0-gvisor`).

Why an override file and not just `runtime: runsc`: gVisor has its own network stack, so
Docker's built-in DNS (`127.0.0.11`) doesn't work inside the sandbox. Workers can't
resolve `rabbitmq` or the CloudAMQP host, and crash at startup. The override files
work around this (fixed IP + `/etc/hosts` for local RabbitMQ; default bridge network
for CloudAMQP).

## Clean up
```bash
docker compose -f docker-compose.cloudamqp.yml down -v   # removes workers + volume
```
> ⚠️ The `.env` holds a real CloudAMQP password. It is git-ignored; rotate it in the
> CloudAMQP dashboard when you're done testing.

## Troubleshooting
- **`AttributeError: 'super' object has no attribute 'transform'`** — WeasyPrint/pydyf
  version mismatch. Pin `pydyf==0.10.0` with `weasyprint==62.3` (already pinned here).
- **Jobs stay "processing":** `docker compose -f docker-compose.cloudamqp.yml logs -f worker`.
- **WeasyPrint build fails:** `docker compose build --no-cache worker`.
- **gVisor workers log `Temporary failure in name resolution`:** you used
  `runtime: runsc` without the gVisor override file. See "Enable gVisor" above.
