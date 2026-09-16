"""Export the pinned official Open Images detector for IRIS (no training data needed)."""
from pathlib import Path
import hashlib
import json
import shutil
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'android/app/src/main/assets/models'
WEIGHTS = ROOT / '.models/yolov8n-oiv7.pt'
URL = 'https://github.com/ultralytics/assets/releases/download/v8.2.0/yolov8n-oiv7.pt'
SOURCE_HASH = '3851dfbf39ed2a076b1f39215cc22dba64eb5646f282bf964703785b0bed6a41'

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

    WEIGHTS.parent.mkdir(parents=True, exist_ok=True)
    if not WEIGHTS.exists():
        temporary = WEIGHTS.with_suffix('.part')
        with urllib.request.urlopen(URL, timeout=60) as source, temporary.open('wb') as target:
            shutil.copyfileobj(source, target)
        assert digest(temporary) == SOURCE_HASH, 'Source weights checksum mismatch'
        temporary.replace(WEIGHTS)
    assert digest(WEIGHTS) == SOURCE_HASH, 'Source weights checksum mismatch'
    # Single-threaded reference avoids the local PyTorch CPU thread instability.
    torch.set_num_threads(1)
    torch.backends.mkldnn.enabled = False
    model = YOLO(str(WEIGHTS))
    model.model.float().eval()
    model.model.fuse()
    assert len(model.names) == 601
    output = Path(model.export(format='onnx', imgsz=640, opset=17, simplify=False,
                              dynamic=False, half=False, device='cpu', batch=1))
    onnx.checker.check_model(str(output))
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    session = ort.InferenceSession(str(output), options, providers=['CPUExecutionProvider'])
    # Exporter configures the process thread pool; restore the deterministic reference.
    torch.set_num_threads(1)
    reference_model = YOLO(str(WEIGHTS)).model.float().eval()
    reference_model.fuse()
    reference_model.requires_grad_(False)
    sample = np.random.default_rng(7).random((1, 3, 640, 640), dtype=np.float32)
    with torch.no_grad():
        reference = reference_model(torch.from_numpy(sample))[0].numpy().copy()
        repeated = reference_model(torch.from_numpy(sample))[0].numpy().copy()
    np.testing.assert_allclose(reference, repeated, rtol=.0001, atol=.0001)
    actual = session.run(None, {session.get_inputs()[0].name: sample})[0]
    assert actual.shape == (1, 605, 8400) and np.isfinite(actual).all()
    np.testing.assert_allclose(actual, reference, rtol=.005, atol=.005)
    print(f'ONNX matches PyTorch, max error {np.max(np.abs(actual-reference)):.6f}', flush=True)
    ASSETS.mkdir(parents=True, exist_ok=True)
    destination = ASSETS / 'objects_oiv7.onnx'
    shutil.copyfile(output, destination)
    translations = json.loads((ROOT / 'scripts/object_labels_id.json').read_text(encoding='utf-8'))
    names = [model.names[i] for i in range(601)]
    assert set(names) == set(translations), 'Translation coverage must match all model classes'
    labels_file = ASSETS / 'objects_labels.json'
    labels_file.write_text(json.dumps([translations[name] for name in names], ensure_ascii=False) + '\n', encoding='utf-8')
    (ROOT / 'evaluation/object_classes.json').write_text(json.dumps([
        {'id': i, 'source': name, 'label': translations[name]} for i, name in enumerate(names)
    ], ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    lock_path = ROOT / 'models.lock.json'
    manifest = json.loads(lock_path.read_text(encoding='utf-8')) if lock_path.exists() else {}
    manifest['objects'] = {
        'file': destination.name, 'sha256': digest(destination), 'url': URL,
        'sourceSha256': SOURCE_HASH, 'license': 'AGPL-3.0 (Ultralytics)',
        'provenance': 'Ultralytics YOLOv8n Open Images V7, official assets v8.2.0',
        'ultralyticsVersion': ultralytics.__version__, 'torchVersion': torch.__version__,
        'onnxVersion': onnx.__version__, 'classes': 601,
        'input': 'RGB float32 /255 NCHW [1,3,640,640], letterbox RGB 114',
        'output': 'float32 [1,605,8400], xywh pixel coordinates and 601 class scores',
        'scoreThreshold': .4, 'nmsIou': .5, 'maxResults': 10,
    }
    manifest['objectLabels'] = {'file': labels_file.name, 'sha256': digest(labels_file)}
    for path in [lock_path, ASSETS / 'manifest.json']:
        path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print('IRIS detector and all 601 Indonesian labels packaged and checksummed.', flush=True)

if __name__ == '__main__':
    main()
