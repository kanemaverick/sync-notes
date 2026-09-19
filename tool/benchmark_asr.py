"""Reproducible offline smoke benchmark, not a general accuracy score.

uv run --with sherpa-onnx==1.13.8 --with numpy python tool/benchmark_asr.py
"""
import json
from pathlib import Path
import time
import wave

import numpy as np
import sherpa_onnx

root = Path(__file__).resolve().parents[1]
results = []
for name in ("asr", "asr_bilingual"):
    model = root / "assets" / name
    started = time.perf_counter()
    recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=str(model / "tokens.txt"),
        encoder=str(model / "encoder.int8.onnx"),
        decoder=str(model / "decoder.onnx"),
        joiner=str(model / "joiner.int8.onnx"),
        num_threads=2,
        model_type="zipformer",
        enable_endpoint_detection=True,
        decoding_method="modified_beam_search" if name == "asr_bilingual" else "greedy_search",
        modeling_unit="cjkchar+bpe" if name == "asr_bilingual" else "cjkchar",
        bpe_vocab=str(model / "bpe.vocab") if name == "asr_bilingual" else "",
    )
    load_seconds = time.perf_counter() - started
    for clip in sorted((root / "test/fixtures/asr").glob("*.wav")):
        with wave.open(str(clip)) as wav:
            assert wav.getnchannels() == 1 and wav.getsampwidth() == 2
            rate = wav.getframerate()
            samples = np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2").astype(np.float32) / 32768
        stream = recognizer.create_stream()
        audio_seconds = len(samples) / rate
        started = time.perf_counter()
        parts = []
        for index in range(0, len(samples), 1600):
            stream.accept_waveform(rate, samples[index:index + 1600])
            while recognizer.is_ready(stream):
                recognizer.decode_stream(stream)
            if recognizer.is_endpoint(stream):
                parts.append(recognizer.get_result(stream))
                recognizer.reset(stream)
        stream.accept_waveform(rate, np.zeros(int(rate * 0.8), dtype=np.float32))
        stream.input_finished()
        while recognizer.is_ready(stream):
            recognizer.decode_stream(stream)
        parts.append(recognizer.get_result(stream))
        elapsed = time.perf_counter() - started
        results.append(dict(model=name, sample=clip.name, audio_seconds=audio_seconds,
                            load_seconds=round(load_seconds, 3), decode_seconds=round(elapsed, 3),
                            rtf=round(elapsed / audio_seconds, 3), text=" ".join(p for p in parts if p)))
print(json.dumps(results, ensure_ascii=False, indent=2))
