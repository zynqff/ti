# VibeTalk Audio Lab — fixed benchmark baseline

This patch removes all fake benchmark values and passthrough model stubs.

## What is real in this patch
- Recording/playback remain local.
- Benchmark processes the same Original Float32 PCM independently for each processor.
- RNNoiseProcessor calls the native RNNoise API (`rnnoise_create`, `rnnoise_process_frame`, `rnnoise_destroy`).
- TTFA is measured from benchmark start to first non-empty processed chunk (processing-only TTFA for offline WAV benchmark).
- Per-chunk latency, P50, P95, max, total time and RTF are measured.
- CPU is derived from task thread CPU time; RAM from task VM resident size.
- No random/constant placeholder metrics.
- DFNet2/DFNet3 return NOT IMPLEMENTED instead of pretending to process audio.

## Critical missing artifact in the supplied project
The supplied RNNoise folder is incomplete: its v0.2 sources reference generated `rnnoise_data.c/rnnoise_data.h` and `osce.h`, but those files are absent. The official RNNoise build also treats the generated model weights as separate model artifacts. Do not replace them with fake data.

Therefore this patch is the correct code/wiring, but the supplied ZIP still needs a complete RNNoise model/source set before the RNNoise target can link.

## DFNet status
The ZIP contains ONNX files, but no ONNX Runtime/CoreML execution code and no DeepFilterNet feature extraction/state pipeline. Those models cannot be honestly treated as raw-audio processors. This patch deliberately reports NOT IMPLEMENTED.

## DTLN2 correction
The former `DeepFilterNet2 Lite` slot is now correctly treated as DTLN2. The supplied ~2.5 MB ONNX is the second stage (`dtln2.onnx`) of the canonical two-stage 16 kHz DTLN streaming model. Codemagic downloads stage 1 (`dtln1.onnx`) automatically, while the supplied file remains the stage-2 model. The bridge implements the 512-sample / 128-sample-shift streaming pipeline and persistent model states. The app accepts the lab's 48 kHz input and resamples to/from 16 kHz for DTLN2.
