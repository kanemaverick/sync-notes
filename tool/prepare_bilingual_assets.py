"""Package only the required runtime files from the official sherpa archive.

uv run --with sentencepiece python tool/prepare_bilingual_assets.py ARCHIVE
The archive is read by exact member name; no paths or links are extracted.
"""
import hashlib
import json
from pathlib import Path
import sys
import tarfile

import sentencepiece as spm

ROOT = Path(__file__).resolve().parents[1]
MODEL = "sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16"
destination = ROOT / "assets/asr_bilingual"
destination.mkdir(parents=True, exist_ok=True)
names = {
    "encoder-epoch-99-avg-1.int8.onnx": "encoder.int8.onnx",
    "decoder-epoch-99-avg-1.int8.onnx": "decoder.onnx",
    "joiner-epoch-99-avg-1.int8.onnx": "joiner.int8.onnx",
    "tokens.txt": "tokens.txt",
}
with tarfile.open(sys.argv[1], "r:bz2") as archive:
    for source, target in names.items():
        member = archive.getmember(f"{MODEL}/{source}")
        assert member.isfile() and member.size < 100_000_000
        (destination / target).write_bytes(archive.extractfile(member).read())
    sp = spm.SentencePieceProcessor(model_proto=archive.extractfile(f"{MODEL}/bpe.model").read())
    (destination / "bpe.vocab").write_text(
        "".join(f"{sp.id_to_piece(i)}\t{sp.get_score(i)}\n" for i in range(sp.get_piece_size())),
        encoding="utf-8",
    )
    samples = ROOT / "test/fixtures/asr"
    samples.mkdir(parents=True, exist_ok=True)
    for sample in ("0.wav", "2.wav"):
        (samples / sample).write_bytes(archive.extractfile(f"{MODEL}/test_wavs/{sample}").read())

for model_dir in (ROOT / "assets/asr", destination):
    manifest = {}
    for file in sorted(model_dir.iterdir()):
        if file.suffix in (".onnx", ".txt", ".vocab"):
            data = file.read_bytes()
            manifest[file.name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    (model_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Packaged {MODEL}; generated model checksums and two official test clips.")
