# Offline ASR model

The bundled files are the quantized runtime subset of
`sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23` from the official
sherpa-onnx ASR model release.

Source and model documentation:
https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-transducer/zipformer-transducer-models.html

The app uses the 16 kHz mono streaming recognizer and keeps transcription
fully on device. The original model archive and test WAV files are not bundled.
