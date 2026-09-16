"""Fetch the pinned Qwen model, keeping download chunks outside Android assets."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request

from fetch_verified import fetch

ROOT = Path(__file__).resolve().parents[1]
entry = json.loads((ROOT / "models.lock.json").read_text(encoding="utf-8"))["qwen"]
target = ROOT / "android/app/src/main/assets/models" / entry["file"]

def verified(path):
    if not path.exists():
        return False
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() == entry["sha256"]

if not verified(target):
    cached = ROOT / ".models/qwen35_mm_q8_ekv2048.litertlm"
    fetch([entry["url"]], cached, entry["sourceSize"], entry["sourceSha256"])
    template = ROOT / ".models/qwen35-tokenizer-config.json"
    if not template.exists():
        urllib.request.urlretrieve(entry["url"].rsplit("/", 1)[0] + "/tokenizer_config.json", template)
    subprocess.run([sys.executable, str(ROOT / "scripts/prepare_qwen35_bundle.py")], check=True)
assert verified(target), "Qwen checksum mismatch"
print(f"Verified Qwen model: {target}")
