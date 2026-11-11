"""
Fire N PDF jobs at the API concurrently, then poll until all are done.
Prints total wall-clock time so you can compare worker counts.

Standard library only -- no pip install needed.
    python3 scripts/load_test.py           # 200 jobs, 100 concurrent submits
    N=100 CONCURRENCY=100 python3 scripts/load_test.py
"""
import json
import os
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = os.getenv("API_URL", "http://localhost:8000")
N = int(os.getenv("N", "200"))
CONCURRENCY = int(os.getenv("CONCURRENCY", "100"))

HTML_TMPL = (
    '<html><body style="font-family: DejaVu Sans;">'
    "<h1>Invoice #{i}</h1>"
    "<p>Hello user {i}, this is your generated PDF.</p>"
    "<p>Rendered in an isolated worker sandbox.</p>"
    "</body></html>"
)


def _post(path, payload):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"{API}{path}", data=data, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def _get(path):
    with urllib.request.urlopen(f"{API}{path}", timeout=30) as r:
        return json.load(r)


def submit(i):
    return _post("/pdf", {"html": HTML_TMPL.format(i=i)})["job_id"]


def is_done(job_id):
    return _get(f"/pdf/{job_id}").get("status") == "done"


def main():
    start = time.time()

    with ThreadPoolExecutor(max_workers=CONCURRENCY) as ex:
        job_ids = list(ex.map(submit, range(N)))
    print(f"Submitted {len(job_ids)} jobs in {time.time() - start:.2f}s "
          f"({CONCURRENCY} concurrent)")

    pending = set(job_ids)
    while pending:
        with ThreadPoolExecutor(max_workers=CONCURRENCY) as ex:
            flags = list(ex.map(is_done, pending))
        pending = {jid for jid, done in zip(pending, flags) if not done}
        print(f"  {len(job_ids) - len(pending)}/{len(job_ids)} done "
              f"(t+{time.time() - start:.1f}s)")
        if pending:
            time.sleep(1)

    print(f"ALL {len(job_ids)} PDFs ready in {time.time() - start:.2f}s")


if __name__ == "__main__":
    main()
