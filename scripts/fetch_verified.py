"""Resumable ranged artifact download with a mandatory publisher SHA-256."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
from pathlib import Path
import time
import socket
from functools import lru_cache
import urllib.request

# Reuse successful DNS resolutions during a download; transient local DNS failures
# must not discard already-working CDN addresses. TLS hostname checks remain intact.
_resolve = socket.getaddrinfo
@lru_cache(maxsize=64)
def _cached_resolve(host, port, family=0, type=0, proto=0, flags=0):
    return _resolve(host, port, socket.AF_INET if family == 0 else family, type, proto, flags)
socket.getaddrinfo = _cached_resolve

def fetch(urls, output, size, sha256, workers=8):
    algorithm = "sha1" if len(sha256) == 40 else "sha256"
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        with output.open("rb") as existing:
            if hashlib.file_digest(existing, algorithm).hexdigest() == sha256:
                return
    parts = output.parent / (output.name + ".parts")
    parts.mkdir(exist_ok=True)
    block = 1024 * 1024
    count = (size + block - 1) // block

    def part(index):
        start = index * block
        end = min(size, start + block) - 1
        path = parts / str(index)
        if path.exists() and path.stat().st_size == end - start + 1:
            return
        for attempt in range(8):
            try:
                uri = urls[attempt % len(urls)]
                request = urllib.request.Request(uri, headers={"Range": f"bytes={start}-{end}", "Accept-Encoding": "identity", "User-Agent": "SahabatNetra/1"})
                with urllib.request.urlopen(request, timeout=45) as response:
                    if response.status != 206 or response.headers.get("Content-Range", "") != f"bytes {start}-{end}/{size}":
                        raise ValueError("Server did not return the requested byte range")
                    data = response.read(end - start + 2)
                if len(data) != end - start + 1:
                    raise ValueError("Incomplete range")
                path.write_bytes(data)
                if index % 16 == 0: print(f"Downloaded part {index + 1}/{count}", flush=True)
                return
            except Exception:
                if attempt == 7: raise
                time.sleep(1)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        list(pool.map(part, range(count)))
    temporary = output.with_suffix(output.suffix + ".verified-part")
    digest = hashlib.new(algorithm)
    with temporary.open("wb") as stream:
        for i in range(count):
            data = (parts / str(i)).read_bytes()
            stream.write(data); digest.update(data)
    if digest.hexdigest() != sha256:
        raise ValueError(f"Publisher {algorithm} mismatch; artifact rejected")
    temporary.replace(output)
    print(f"Verified {output.name}: {sha256}", flush=True)

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--url", action="append", required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--size", type=int, required=True)
    p.add_argument("--sha256", "--checksum", dest="sha256", required=True)
    a = p.parse_args()
    fetch(a.url, a.output, a.size, a.sha256)
