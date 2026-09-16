"""Export pinned YOLO26n-depth to Android; run with the isolated depth exporter.

PowerShell: $env:PYTHONPATH='.tools/depth-python'; python scripts/prepare_depth.py
Requires ultralytics==8.4.150, filelock==3.20.3 and the existing torch/ONNX stack.
"""
from pathlib import Path
import hashlib
import json
import shutil
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'android/app/src/main/assets/models'
CACHE = ROOT / '.models'
URL = 'https://github.com/ultralytics/assets/releases/download/v8.4.0/yolo26n-depth.pt'
SOURCE_HASH = 'befed1b8561d8b2eaa66274b070cdfc9c44853bda6d6d62a04759f9383af74e9'
SIZE = 640


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    import numpy as np
    import onnx
    import onnxruntime as ort
    import torch
    import ultralytics
    from ultralytics import YOLO
    assert ultralytics.__version__ == '8.4.150', 'Use isolated ultralytics==8.4.150 exporter'
    CACHE.mkdir(exist_ok=True)
    weights = CACHE / 'yolo26n-depth.pt'
    if not weights.exists():
        partial = weights.with_suffix('.part')
        with urllib.request.urlopen(URL, timeout=60) as source, partial.open('wb') as target:
            shutil.copyfileobj(source, target)
        assert digest(partial) == SOURCE_HASH, 'Publisher SHA-256 mismatch'
        partial.replace(weights)
    assert digest(weights) == SOURCE_HASH, 'Publisher SHA-256 mismatch'
    torch.set_num_threads(1)
    torch.backends.mkldnn.enabled = False
    model = YOLO(str(weights), task='depth').model.float().eval()
    model.fuse()
    model.requires_grad_(False)
    # The official export branch includes metric calibration and 4x bilinear upsampling.
    model.model[-1].export = True
    sample = torch.from_numpy(np.random.default_rng(7).random((1, 3, SIZE, SIZE), dtype=np.float32))
    exported = CACHE / 'depth_yolo26n.onnx'
    with torch.no_grad():
        torch.onnx.export(model, sample, str(exported), input_names=['image'], output_names=['depth'],
                          opset_version=17, do_constant_folding=True)
    onnx.checker.check_model(str(exported))
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(exported), options, providers=['CPUExecutionProvider'])
    comparisons = []
    for name, value in [('random', sample.numpy()), ('gray', np.full(sample.shape, 114 / 255, np.float32)),
                        ('black', np.zeros(sample.shape, np.float32))]:
        with torch.no_grad():
            expected = model(torch.from_numpy(value)).numpy().copy()
        started = time.perf_counter()
        actual = session.run(None, {'image': value})[0]
        elapsed = (time.perf_counter() - started) * 1000
        assert actual.shape == (1, 1, SIZE, SIZE) and np.isfinite(actual).all() and (actual > 0).all()
        np.testing.assert_allclose(actual, expected, rtol=.005, atol=.005)
        comparisons.append({'input': name, 'maxAbsoluteError': float(np.max(np.abs(actual - expected))),
                            'desktopOnnxMs': elapsed})
        print(comparisons[-1], flush=True)
    del session
    destination = ASSETS / exported.name
    shutil.copyfile(exported, destination)
    manifest = json.loads((ASSETS / 'manifest.json').read_text(encoding='utf-8'))
    manifest.pop('depthIndoor', None)
    manifest.pop('depthOutdoor', None)
    manifest['depth'] = {
        'file': destination.name, 'sha256': digest(destination), 'url': URL,
        'sourceSha256': SOURCE_HASH, 'license': 'AGPL-3.0 (Ultralytics)',
        'provenance': 'Official Ultralytics assets v8.4.0 YOLO26n-depth',
        'ultralyticsVersion': ultralytics.__version__, 'torchVersion': torch.__version__,
        'onnxVersion': onnx.__version__, 'input': 'RGB /255 NCHW [1,3,640,640], letterbox RGB 114',
        'output': 'positive metric depth [1,1,640,640], metres; no per-image scale alignment',
        'validation': comparisons,
    }
    for path in [ASSETS / 'manifest.json', ROOT / 'models.lock.json']:
        path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    # Preserve previous binaries outside the APK for comparisons and rollback.
    for name in ['depth_indoor.onnx', 'depth_outdoor.onnx']:
        old = ASSETS / name
        if old.exists():
            backup = CACHE / ('previous-' + name)
            if backup.exists():
                assert digest(backup) == digest(old), 'Previous model backup differs'
                old.unlink()
            else:
                old.replace(backup)
    print(f'Packaged {destination.name}: {destination.stat().st_size} bytes; numerical parity passed.', flush=True)


if __name__ == '__main__':
    main()
