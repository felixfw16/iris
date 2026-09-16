"""Populate Gradle's content-addressed cache for a stalled public Maven artifact."""
import argparse
from pathlib import Path
import re
import shutil
import urllib.request
from fetch_verified import fetch

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("coordinate")
    parser.add_argument("--repo", default="https://repo.maven.apache.org/maven2")
    parser.add_argument("--extension", choices=["jar", "aar"], default="jar")
    args = parser.parse_args()
    group, artifact, version = args.coordinate.split(":")
    if not all(re.fullmatch(r"[A-Za-z0-9_.-]+", x) for x in (group, artifact, version)):
        raise ValueError("Invalid Maven coordinate")
    name = f"{artifact}-{version}.{args.extension}"
    url = f"{args.repo}/{group.replace('.', '/')}/{artifact}/{version}/{name}"
    with urllib.request.urlopen(urllib.request.Request(url, method="HEAD"), timeout=30) as response:
        size = int(response.headers["Content-Length"])
    with urllib.request.urlopen(url + ".sha1", timeout=30) as response:
        checksum = response.read().decode().strip().split()[0]
    if not re.fullmatch(r"[0-9a-fA-F]{40}", checksum):
        raise ValueError("Missing publisher checksum")
    output = Path(__file__).resolve().parents[1] / ".tools/maven" / name
    fetch([url], output, size, checksum.lower())
    directory = Path.home() / ".gradle/caches/modules-2/files-2.1" / group / artifact / version / checksum.lower()
    directory.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(output, directory / name)
    print(f"Cached {args.coordinate}", flush=True)

if __name__ == "__main__":
    main()
