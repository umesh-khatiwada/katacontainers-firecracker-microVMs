"""
API service.

- POST /pdf          -> publish a PDF job to RabbitMQ, return a job_id immediately
- GET  /pdf/{id}     -> report status; when ready, return a download URL
- GET  /download/{id}-> stream the finished PDF
- GET  /health       -> liveness check

Storage: a shared volume at STORAGE_DIR, written by workers and read here.
A job is "done" when <STORAGE_DIR>/<job_id>.pdf exists.
Supports both amqp:// (local) and amqps:// (CloudAMQP / TLS).
"""
import json
import os
import ssl
import threading
import uuid

import pika
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://guest:guest@rabbitmq:5672/")
QUEUE = os.getenv("PDF_QUEUE", "pdf_jobs")
STORAGE_DIR = os.getenv("STORAGE_DIR", "/data")

app = FastAPI(title="gVisor PDF Service")


def make_params() -> pika.URLParameters:
    params = pika.URLParameters(RABBITMQ_URL)
    if RABBITMQ_URL.startswith("amqps") and not params.ssl_options:
        params.ssl_options = pika.SSLOptions(ssl.create_default_context())
    return params


# One shared publisher connection guarded by a lock. Keeps the API to a SINGLE
# broker connection no matter how many concurrent requests arrive (important on
# managed brokers with connection caps). pika BlockingConnection is not
# thread-safe, so the lock serializes the (fast) publish calls.
_lock = threading.Lock()
_conn: pika.BlockingConnection | None = None
_ch = None


def _ensure_channel():
    global _conn, _ch
    if _conn is None or _conn.is_closed:
        _conn = pika.BlockingConnection(make_params())
        _ch = _conn.channel()
        _ch.queue_declare(queue=QUEUE, durable=True)
    return _ch


def publish_job(payload: dict) -> None:
    with _lock:
        try:
            ch = _ensure_channel()
            ch.basic_publish(
                exchange="",
                routing_key=QUEUE,
                body=json.dumps(payload),
                properties=pika.BasicProperties(delivery_mode=2),  # persistent
            )
        except (pika.exceptions.AMQPError, OSError):
            global _conn
            _conn = None  # drop dead connection, retry once on a fresh one
            ch = _ensure_channel()
            ch.basic_publish(
                exchange="",
                routing_key=QUEUE,
                body=json.dumps(payload),
                properties=pika.BasicProperties(delivery_mode=2),
            )


class PdfRequest(BaseModel):
    html: str
    filename: str | None = None


@app.post("/pdf")
def create_pdf(req: PdfRequest):
    job_id = str(uuid.uuid4())
    publish_job(
        {
            "job_id": job_id,
            "html": req.html,
            "filename": req.filename or f"{job_id}.pdf",
        }
    )
    return {"job_id": job_id, "status": "queued"}


@app.get("/pdf/{job_id}")
def get_pdf(job_id: str):
    if not os.path.exists(os.path.join(STORAGE_DIR, f"{job_id}.pdf")):
        return {"job_id": job_id, "status": "processing"}
    return {
        "job_id": job_id,
        "status": "done",
        "download_url": f"http://localhost:8000/download/{job_id}",
    }


@app.get("/download/{job_id}")
def download(job_id: str):
    path = os.path.join(STORAGE_DIR, f"{job_id}.pdf")
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="not ready")
    return FileResponse(path, media_type="application/pdf", filename=f"{job_id}.pdf")


@app.get("/health")
def health():
    return {"ok": True}
