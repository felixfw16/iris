"""Repack the third-party export with explicit hybrid-attention runtime metadata."""
from pathlib import Path
import sys
import hashlib
import io
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools/litert-validation/python"))
from litert_lm_builder.litertlm_builder import LitertLmFileBuilder
from litert_lm_builder.runtime.proto import executor_metadata_pb2 as executor_pb
from litert_lm_builder.runtime.proto import llm_metadata_pb2 as llm_pb
from google.protobuf import text_format
from litert_lm_builder.litertlm_peek import read_litertlm_header, get_model_type

source = ROOT / ".models/qwen35_mm_q8_ekv2048.litertlm"
source_hash = "92999fe4a9242c983e99892d6e57f368e8cd7a4534bc9a383a9551155b7f70a5"
with source.open("rb") as stream:
    assert hashlib.file_digest(stream, "sha256").hexdigest() == source_hash
unpacked = ROOT / ".models/qwen35-unpacked"
if not (unpacked / "model.toml").exists():
    LitertLmFileBuilder.unpack(str(source), str(unpacked))
executor = executor_pb.ExecutorMetadata()
executor.llm_executor_metadata.max_history_size = 1
for layer in range(24):
    for kind in ("k", "v"):
        name = f"kv_cache_{kind}_{layer}"
        state = executor.llm_executor_metadata.state_buffers.add(
            prefill_input_name=name, prefill_output_name=name,
            decode_input_name=name, decode_output_name=name,
        )
        if layer % 4 != 3:
            state.type = executor_pb.StateBuffer.TYPE_LINEAR_ATTENTION
        else:
            state.type = (executor_pb.StateBuffer.TYPE_GLOBAL_KEY_CACHE if kind == "k"
                          else executor_pb.StateBuffer.TYPE_GLOBAL_VALUE_CACHE)
            state.sequence_axis = 1
            state.maximum_sequence_length = 2048
executor_path = unpacked / "ExecutorMetadata.pbtext"
executor_path.write_text(text_format.MessageToString(executor), encoding="utf-8")

# Preserve source weights and make the existing generation prefix honor the switch.
llm = llm_pb.LlmMetadata()
llm_path = unpacked / "LlmMetadataProto.pbtext"
text_format.Parse(llm_path.read_text(encoding="utf-8"), llm)
template_config = ROOT / ".models/qwen35-tokenizer-config.json"
assert hashlib.sha256(template_config.read_bytes()).hexdigest() == "49e2b6e395f959f077f1e992b338919c0d4a9732fc6e613995e06557f843500c"
llm.jinja_prompt_template = json.loads(template_config.read_text(encoding="utf-8"))["chat_template"]
llm_path.write_text(text_format.MessageToString(llm), encoding="utf-8")
builder = LitertLmFileBuilder.from_toml_file(str(unpacked / "model.toml"))
builder.add_executor_metadata(str(executor_path))
output = ROOT / ".models/qwen35_0_8b_iris.litertlm"
with output.open("wb") as stream:
    builder.build(stream)
print("Repacked with hybrid state metadata:", output)

def weight_hashes(path):
    sections = read_litertlm_header(str(path), io.StringIO()).SectionMetadata()
    result = {}
    with path.open("rb") as stream:
        for i in range(sections.ObjectsLength()):
            section = sections.Objects(i)
            kind = get_model_type(section)
            if kind is None:
                continue
            stream.seek(section.BeginOffset())
            remaining = section.EndOffset() - section.BeginOffset()
            digest = hashlib.sha256()
            while remaining:
                block = stream.read(min(remaining, 1024 * 1024))
                assert block
                digest.update(block)
                remaining -= len(block)
            result[kind] = digest.hexdigest()
    return result

before, after = weight_hashes(source), weight_hashes(output)
assert before and before == after, "Repacking changed model weights"
print("Verified unchanged model sections:", sorted(before))
with output.open("rb") as stream:
    digest = hashlib.file_digest(stream, "sha256").hexdigest()
entry = dict(file=output.name, sha256=digest, size=output.stat().st_size,
    url="https://huggingface.co/GabrieleConte/Qwen3.5-0.8B-LiteRT/resolve/766ec4afaaeeda64da162c458bac1efc0d27cf9e/qwen35_mm_q8_ekv2048.litertlm",
    sourceSha256=source_hash, sourceSize=1159757824,
    provenance="GabrieleConte revision 766ec4afaaeeda64da162c458bac1efc0d27cf9e; IRIS hybrid executor metadata and publisher tokenizer chat template; unchanged model weights",
    license="Apache-2.0", quantization="dynamic INT8", contextTokens=2048,
    runtime="LiteRT-LM Android 0.17.0", modelSectionHashes=after)
assets = ROOT / "android/app/src/main/assets/models"
shutil.copyfile(output, assets / output.name)
old = assets / "qwen3_0_6b_int4.litertlm"
if old.exists():
    backup = ROOT / ".models/previous-qwen3_0_6b_int4.litertlm"
    assert not backup.exists(), "Previous Qwen backup already exists"
    old.rename(backup)
for path in (ROOT / "models.lock.json", assets / "manifest.json"):
    manifest = json.loads(path.read_text(encoding="utf-8"))
    manifest["qwen"] = entry
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print("Prepared Android model:", digest)
