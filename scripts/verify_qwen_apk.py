"""Audit the final APK against the pinned model manifest."""
import hashlib
import json
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
apk = root / "build/app/outputs/flutter-apk/app-release.apk"
with zipfile.ZipFile(apk) as archive:
    names = archive.namelist()
    assert not any(".parts/" in name for name in names), "Download chunks packaged"
    manifest = json.loads(archive.read("assets/models/manifest.json"))
    for key, entry in manifest.items():
        if not isinstance(entry, dict) or "file" not in entry:
            continue
        with archive.open("assets/models/" + entry["file"]) as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        assert digest == entry["sha256"], key
        print("Verified packaged model:", key)
    assert any("liblitertlm" in name for name in names), "LiteRT-LM runtime missing"
with apk.open("rb") as stream:
    print("APK SHA256:", hashlib.file_digest(stream, "sha256").hexdigest())
print("APK bytes:", apk.stat().st_size)
model = root / "android/app/src/main/assets/models" / manifest["qwen"]["file"]
with model.open("rb") as stream:
    header = stream.read(2 * 1024 * 1024)
offset = header.find(b"enable_thinking")
print("Thinking template metadata offset:", offset)
if offset >= 0:
    print(repr(header[max(0, offset - 150):offset + 300]))
