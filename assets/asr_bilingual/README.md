# Offline Chinese-English ASR

Runtime: sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16.

Source: https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models
Model card (Apache-2.0): https://huggingface.co/csukuangfj/k2fsa-zipformer-bilingual-zh-en-t
Original training model: https://huggingface.co/pfluo/k2fsa-zipformer-chinese-english-mixed

Only the INT8 encoder, decoder and joiner plus tokens and exported BPE vocabulary
are packaged. `decoder.onnx` is the renamed INT8 decoder (the common app filename).
`manifest.json` contains file sizes and SHA-256 checksums. The app verifies cached
files and repairs them from its bundled assets before use.

Reproduce with `tool/prepare_bilingual_assets.py` using the official archive.
The original lightweight Chinese model remains selectable in Settings.
The model is not trained specifically for a user's conference: names, accents,
distant microphones and abbreviations still require listening back to the audio.
