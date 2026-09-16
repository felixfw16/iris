"""Audit the final APK against the pinned model manifest."""
import hashlib
import json
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
apk = root / "build/app/outputs/flutter-apk/app-release.apk"
locked = json.loads((root / "models.lock.json").read_text(encoding="utf-8"))
required = {"objects", "objectLabels", "face", "speech", "depth", "qwen"}
with zipfile.ZipFile(apk) as archive:
    names = archive.namelist()
    assert not any(".parts/" in name for name in names), "Download chunks packaged"
    manifest = json.loads(archive.read("assets/models/manifest.json"))
    assert required <= manifest.keys(), "Required model entries missing"
    for key in required:
        assert manifest[key]["file"] == locked[key]["file"], f"Wrong packaged model: {key}"
        assert manifest[key]["sha256"] == locked[key]["sha256"], f"Model differs from lock: {key}"
    for key, entry in manifest.items():
        if not isinstance(entry, dict) or "file" not in entry:
            continue
        with archive.open("assets/models/" + entry["file"]) as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        assert digest == entry["sha256"], key
        print("Verified packaged model:", key)
    assert any("liblitertlm" in name for name in names), "LiteRT-LM runtime missing"
    for library in ("libapp.so", "libflutter.so", "libnetra_whisper.so"):
        assert f"lib/arm64-v8a/{library}" in names, f"ARM64 runtime missing: {library}"
    with archive.open("assets/models/" + manifest["qwen"]["file"]) as stream:
        header = stream.read(2 * 1024 * 1024)
with apk.open("rb") as stream:
    print("APK SHA256:", hashlib.file_digest(stream, "sha256").hexdigest())
print("APK bytes:", apk.stat().st_size)
offset = header.find(b"enable_thinking")
assert offset >= 0, "Packaged Qwen thinking template missing"
print("Thinking template metadata offset:", offset)
