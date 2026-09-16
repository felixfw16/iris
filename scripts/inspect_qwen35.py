from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
model = root / ".models/qwen35_mm_q8_ekv2048.litertlm"
source = model if model.exists() else model.parent / (model.name + ".parts") / "0"
with source.open("rb") as stream:
    header = stream.read(1000000)
print("Header:", repr(header[:128]))
strings = re.findall(rb"[\x20-\x7e\n\r\t]{15,}", header)
(root / "build/qwen35-header.txt").write_text("\n".join(s.decode("ascii") for s in strings), encoding="utf-8")
for token in (b"enable_thinking", b"qwen", b"jinja", b"tool", b"prefill"):
    i = header.find(token)
    print(token, i, repr(header[max(0, i - 80):i + 250]) if i >= 0 else "")
