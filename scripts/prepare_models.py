"""Fetch pinned model sources; export metric depth to a fixed Android ONNX contract.

Run inside a project venv. No API key required; no user images are transmitted.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import inspect
import json
import os
import subprocess
import sys
import time
import types
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "android/app/src/main/assets/models"
CACHE = ROOT / ".models"
DEPTH_COMMIT = "a561b849ebae10a6f5ef49e26c83cbbcd36c71bf"
FACE_COMMIT = "dbf9732725cf1ab6e06b412651bb4858b5dfe0df"
WHISPER_COMMIT = "5359861c739e955e79d9a303bcbc70fb988958b1"
EXPECTED = {
    "ggml-tiny.bin": (77691713, "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"),
    "hypersim.pth": (99222290, "b782898d8a3e8be1f639de33837ed85e9b4b73e40f8f5e5cd99067588d722545"),
    "vkitti.pth": (99221808, "9203e538d35255c90dda4b7fedb47ff33fe725497bcca3b1e53b3a65ee63f0cb"),
}

def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def download(url, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    expected_size, expected_hash = EXPECTED.get(destination.name, (0, None))
    if destination.exists() and destination.stat().st_size > 1000:
        if expected_hash is None or digest(destination) == expected_hash:
            return destination
    temporary = destination.with_suffix(destination.suffix + ".part")
    print(f"Downloading {destination.name}", flush=True)
    # Verify publisher LFS checksums. Interrupted downloads must never become model assets.
    for attempt in range(8):
        offset = temporary.stat().st_size if temporary.exists() else 0
        if expected_size and offset == expected_size:
            break
        headers = {"User-Agent": "SahabatNetra-research-build/1", "Accept-Encoding": "identity"}
        if offset: headers["Range"] = f"bytes={offset}-"
        request = urllib.request.Request(url + ("?download=true" if "huggingface.co" in url else ""), headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=90) as source:
                status = source.status
                if offset and status != 206:
                    offset = 0
                if status == 206:
                    content_range = source.headers.get("Content-Range", "")
                    if not content_range.startswith(f"bytes {offset}-"):
                        raise ValueError(f"Unexpected byte range: {content_range}")
                with temporary.open("ab" if offset else "wb") as target:
                    while chunk := source.read(256 * 1024):
                        target.write(chunk)
            if not expected_size or temporary.stat().st_size == expected_size:
                break
        except (OSError, ValueError) as error:
            print(f"Retry {destination.name}: {type(error).__name__}", flush=True)
            if attempt == 7: raise
        time.sleep(1)
    if temporary.stat().st_size < 1000:
        raise ValueError(f"Not a model artifact: {destination}")
    if expected_size and temporary.stat().st_size != expected_size:
        raise ValueError(f"Incomplete model: {destination.name} ({temporary.stat().st_size}/{expected_size})")
    if expected_hash and digest(temporary) != expected_hash:
        raise ValueError(f"Publisher checksum mismatch: {destination.name}")
    temporary.replace(destination)
    return destination

def clone(url, destination, revision):
    if (destination / ".git").exists():
        current = subprocess.run(["git", "-C", str(destination), "rev-parse", "HEAD"], capture_output=True, text=True)
        if current.returncode == 0 and current.stdout.strip() == revision and (destination / "metric_depth/depth_anything_v2/dpt.py").exists():
            return
    if not (destination / ".git").exists():
        subprocess.run(["git", "-c", "core.longpaths=true", "clone", "--depth", "1", url, str(destination)], check=True)
    subprocess.run(["git", "-C", str(destination), "fetch", "--depth", "1", "origin", revision], check=True)
    subprocess.run(["git", "-C", str(destination), "-c", "core.longpaths=true", "checkout", "--detach", revision], check=True)

def prepare_legacy():
    ASSETS.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    sources = {
        "face": ("mobilefacenet.tflite", f"https://raw.githubusercontent.com/estebanuri/face_recognition/{FACE_COMMIT}/android/app/src/main/assets/mobile_face_net.tflite", f"estebanuri/face_recognition {FACE_COMMIT}; MobileFaceNet", "Not declared in upstream example repository; see MODEL_CARD.md"),
        "speech": ("ggml-tiny.bin", f"https://huggingface.co/ggerganov/whisper.cpp/resolve/{WHISPER_COMMIT}/ggml-tiny.bin", f"whisper.cpp model conversion {WHISPER_COMMIT}; multilingual tiny", "MIT"),
    }
    depth_sources = {
        "depthIndoor": ("hypersim", "3bc65d4e14a6786a61acec16453c50e12bf5f338", "Hypersim", 20),
        "depthOutdoor": ("vkitti", "c725b8589bdf6ab04072cab74c0467830db80d6d", "VKITTI", 80),
    }
    jobs = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        for name, (filename, url, _, _) in sources.items():
            jobs.append(pool.submit(download, url, ASSETS / filename))
        for _, (dataset, revision, repo, _) in depth_sources.items():
            url = f"https://huggingface.co/depth-anything/Depth-Anything-V2-Metric-{repo}-Small/resolve/{revision}/depth_anything_v2_metric_{dataset}_vits.pth"
            jobs.append(pool.submit(download, url, CACHE / f"{dataset}.pth"))
        for job in jobs:
            job.result()

    clone("https://github.com/DepthAnything/Depth-Anything-V2.git", CACHE / "depth-source", DEPTH_COMMIT)
    sys.path.insert(0, str(CACHE / "depth-source/metric_depth"))
    import torch
    import numpy as np
    import onnx
    import onnxruntime as ort
    from depth_anything_v2.dpt import DepthAnythingV2

    manifest = {}
    for key, (filename, url, provenance, license_name) in sources.items():
        manifest[key] = {"file": filename, "url": url, "sha256": digest(ASSETS / filename), "provenance": provenance, "license": license_name}
    torch.set_num_threads(1)
    torch.use_deterministic_algorithms(True)
    # Avoid platform-specific oneDNN convolution differences in the CPU reference export.
    torch.backends.mkldnn.enabled = False
    torch.manual_seed(7)
    sample = torch.randn(1, 3, 294, 392)
    for key, (dataset, revision, repo, maximum) in depth_sources.items():
        filename = "depth_indoor.onnx" if key == "depthIndoor" else "depth_outdoor.onnx"
        output = ASSETS / filename
        if not output.exists():
            print(f"Exporting {key}, fixed RGB NCHW 294x392", flush=True)
            model = DepthAnythingV2(encoder="vits", features=64, out_channels=[48, 96, 192, 384], max_depth=maximum).eval()
            model.load_state_dict(torch.load(CACHE / f"{dataset}.pth", map_location="cpu", weights_only=True))
            # The input size is fixed: precompute DINO bicubic positional encoding,
            # avoiding exporter-specific Resize scale-factor rounding differences.
            with torch.no_grad():
                original = model(sample).numpy().copy()
                repeated = model(sample).numpy().copy()
                print(f"Reference repeat max error: {np.abs(repeated-original).max():.6f}; training={model.training}", flush=True)
                np.testing.assert_allclose(repeated, original, rtol=.0001, atol=.0001)
                backbone = model.pretrained
                tokens = torch.zeros(1, (294 // 14) * (392 // 14) + 1, backbone.embed_dim)
                position = backbone.interpolate_pos_encoding(tokens, 294, 392).detach().clone()
                backbone.register_buffer("fixed_position", position)
                backbone.interpolate_pos_encoding = types.MethodType(lambda self, x, w, h: self.fixed_position.to(x.dtype), backbone)
                np.testing.assert_allclose(model(sample).numpy(), original, rtol=.0001, atol=.0001)
            partial = output.with_suffix(".onnx.part")
            with torch.no_grad():
                reference = model(sample).numpy()
                print(f"{key} reference range {reference.min():.5f}..{reference.max():.5f}", flush=True)
                export_options = {"dynamo": False} if "dynamo" in inspect.signature(torch.onnx.export).parameters else {}
                torch.onnx.export(model, sample, str(partial), input_names=["image"], output_names=["depth"], opset_version=17, do_constant_folding=True, **export_options)
            onnx.checker.check_model(str(partial))
            session = ort.InferenceSession(str(partial), providers=["CPUExecutionProvider"])
            actual = session.run(None, {"image": sample.numpy()})[0]
            print(f"{key} ONNX range {actual.min():.5f}..{actual.max():.5f}; max error {np.abs(actual-reference).max():.6f}", flush=True)
            np.testing.assert_allclose(actual, reference, rtol=.005, atol=.005)
            assert actual.shape == (1, 294, 392) and np.isfinite(actual).all()
            partial.replace(output)
            del session, model
        manifest[key] = {"file": filename, "sha256": digest(output), "sourceRevision": revision, "exportCodeRevision": DEPTH_COMMIT, "torchVersion": torch.__version__, "onnxVersion": onnx.__version__, "license": "Apache-2.0 (Small)", "input": "RGB float32 ImageNet normalized NCHW [1,3,294,392]", "output": "metric optical-axis depth [1,294,392] in metres", "maxTrainingDepth": maximum}
    (ASSETS / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (ROOT / "models.lock.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    from prepare_objects import main as prepare_objects
    prepare_objects()
    print("All model assets prepared and checksummed. Object/depth ONNX exports verified.", flush=True)

def main():
    if '--legacy-depth' in sys.argv:
        prepare_legacy()
        return
    ASSETS.mkdir(parents=True, exist_ok=True)
    sources = {
        'face': ('mobilefacenet.tflite', f'https://raw.githubusercontent.com/estebanuri/face_recognition/{FACE_COMMIT}/android/app/src/main/assets/mobile_face_net.tflite', 'Not declared in upstream example repository; see MODEL_CARD.md'),
        'speech': ('ggml-tiny.bin', f'https://huggingface.co/ggerganov/whisper.cpp/resolve/{WHISPER_COMMIT}/ggml-tiny.bin', 'MIT'),
    }
    manifest_path = ASSETS / 'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else {}
    for key, (filename, url, license_name) in sources.items():
        path = download(url, ASSETS / filename)
        manifest[key] = {'file': filename, 'url': url, 'sha256': digest(path), 'license': license_name}
    for path in [manifest_path, ROOT / 'models.lock.json']:
        path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    # Keep the 601-class object exporter on its existing pinned environment.
    from prepare_objects import main as prepare_objects
    prepare_objects()
    exporter = ROOT / '.tools/depth-python'
    if not (exporter / 'ultralytics').exists():
        raise RuntimeError('Install ultralytics==8.4.150 and filelock==3.20.3 with --no-deps --target .tools/depth-python; see README.md')
    environment = os.environ.copy()
    environment['PYTHONPATH'] = str(exporter)
    environment['YOLO_CONFIG_DIR'] = str(CACHE / 'yolo-config')
    subprocess.run([sys.executable, str(ROOT / 'scripts/prepare_depth.py')], env=environment, check=True)


if __name__ == "__main__":
    main()
