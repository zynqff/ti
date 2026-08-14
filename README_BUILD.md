# VibeTalk Audio Lab — real native benchmark

## One-command build on Mac

```bash
chmod +x Scripts/build_and_run.sh
./Scripts/build_and_run.sh
```

The script installs the iOS Rust target, downloads official RNNoise model data if missing, builds the official DeepFilterNet Rust realtime runtime for DFNet3 and the native DFNet3 runtime, then runs `xcodebuild` for an unsigned iOS device build.

The app uses 48 kHz mono Float32 PCM. DeepFilterNet's native hop size is obtained from the runtime; the Swift processor requires benchmark chunks to be aligned to that frame size.

### Important
The two ONNX files that were originally in `Resources/Models` are retained for reference, but the actual native runtime uses the official DeepFilterNet Rust runtime and model archives. This is deliberate: the official runtime performs the required STFT/ISTFT, ERB feature extraction, normalization, model inference, lookahead and deep-filter coefficient application. ONNX Runtime alone is not sufficient for this pipeline.
