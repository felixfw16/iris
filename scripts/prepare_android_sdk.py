"""Install exact SDK packages with checksums from Google's repository2-3 metadata.

Uses bounded parallel ranges to cope with interrupted large transfers. Extracts
only validated archive paths into explicitly selected Android SDK directories.
"""
from pathlib import Path
import os
import shutil
import zipfile
from fetch_verified import fetch

ROOT = Path(__file__).resolve().parents[1]
SDK = Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk"
PACKAGES = [
    ("platform-36_r02.zip", 65878410, "2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576", "platforms/android-36"),
    ("build-tools_r36_windows.zip", 58699878, "f16ccffd34de8790dede813a6c7d8e2c11a27b50", "build-tools/36.0.0"),
    ("cmake-3.22.1-windows.zip", 16116742, "292778f32a7d5183e1c49c7897b870653f2d2c1b", "cmake/3.22.1"),
    ("android-ndk-r28c-windows.zip", 748118221, "086bba43ff2f5eb0e387b15c8278bb4e0d89ba1d", "ndk/28.2.13676358"),
]

def main():
    for name, size, checksum, relative in PACKAGES:
        target = (SDK / relative).resolve()
        if not target.is_relative_to(SDK.resolve()):
            raise ValueError("SDK destination escaped its root")
        if (target / "source.properties").exists():
            print(f"Already installed: {relative}", flush=True)
            continue
        archive = ROOT / ".tools" / name
        fetch(["https://dl.google.com/android/repository/" + name], archive, size, checksum, workers=24)
        with zipfile.ZipFile(archive) as source:
            entries = [entry for entry in source.infolist() if not entry.is_dir()]
            # Google archives either wrap everything in one directory or start at bin/.
            roots = {Path(entry.filename).parts[0] for entry in entries}
            strip_root = len(roots) == 1
            for entry in entries:
                parts = Path(entry.filename).parts
                destination = (target / Path(*(parts[1:] if strip_root else parts))).resolve()
                if not destination.is_relative_to(target):
                    raise ValueError("Unsafe SDK archive entry")
                destination.parent.mkdir(parents=True, exist_ok=True)
                with source.open(entry) as src, destination.open("wb") as dst:
                    shutil.copyfileobj(src, dst)
        if not (target / "source.properties").exists():
            raise ValueError(f"SDK package layout mismatch: {relative}")
        print(f"Installed: {relative}", flush=True)

if __name__ == "__main__":
    main()
