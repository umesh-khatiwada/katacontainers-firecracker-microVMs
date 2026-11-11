"""
Worker: the thing you run many copies of (optionally inside gVisor).

Loop: pull one job from RabbitMQ -> render HTML to PDF -> write to shared volume -> ack.

Key reliability settings:
- prefetch_count=1  : grab only one job at a time, so jobs spread evenly across workers.
- manual ack        : ack only AFTER the file is written, so a crash mid-job redelivers it.

Storage: writes <STORAGE_DIR>/<job_id>.pdf atomically (temp file + rename) so the API
never sees a half-written PDF.
"""
import json
import logging
import os
import ssl
import time

import pika
from weasyprint import HTML

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("worker")

RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://guest:guest@rabbitmq:5672/")
QUEUE = os.getenv("PDF_QUEUE", "pdf_jobs")
STORAGE_DIR = os.getenv("STORAGE_DIR", "/data")


def handle(ch, method, _properties, body) -> None:
    try:
        job = json.loads(body)
        job_id = job["job_id"]
        html = job["html"]
        log.info("Rendering job %s", job_id)

        pdf_bytes = HTML(string=html).write_pdf()  # untrusted HTML -> sandbox this!

        final = os.path.join(STORAGE_DIR, f"{job_id}.pdf")
        tmp = final + ".tmp"
        with open(tmp, "wb") as f:
            f.write(pdf_bytes)
        os.replace(tmp, final)  # atomic: API only ever sees the complete file

        ch.basic_ack(delivery_tag=method.delivery_tag)
        log.info("Done job %s (%d bytes)", job_id, len(pdf_bytes))
    except Exception:  # noqa: BLE001 - demo: don't requeue poison messages
        log.exception("Job failed; rejecting without requeue")
        ch.basic_reject(delivery_tag=method.delivery_tag, requeue=False)


def make_params() -> pika.URLParameters:
    params = pika.URLParameters(RABBITMQ_URL)
    if RABBITMQ_URL.startswith("amqps") and not params.ssl_options:
        params.ssl_options = pika.SSLOptions(ssl.create_default_context())
    return params


def connect_with_retry() -> pika.BlockingConnection:
    params = make_params()
    while True:
        try:
            return pika.BlockingConnection(params)
        # OSError covers DNS failures (socket.gaierror), which pika does not wrap.
        except (pika.exceptions.AMQPConnectionError, OSError) as err:
            log.warning("RabbitMQ not ready (%s), retrying in 3s...", err)
            time.sleep(3)


def main() -> None:
    os.makedirs(STORAGE_DIR, exist_ok=True)
    conn = connect_with_retry()
    ch = conn.channel()
    ch.queue_declare(queue=QUEUE, durable=True)
    ch.basic_qos(prefetch_count=1)
    ch.basic_consume(queue=QUEUE, on_message_callback=handle)
    log.info("Worker ready, waiting for jobs on '%s'", QUEUE)
    ch.start_consuming()


if __name__ == "__main__":
    main()
