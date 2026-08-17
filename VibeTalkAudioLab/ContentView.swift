import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var benchmarkManager = BenchmarkManager()

    // FIX: Play buttons used to be enabled unconditionally, even while
    // `benchmarkManager.isRunning` was still true. DFNet3 is the heaviest of
    // the three processors (full neural-net inference per 10ms frame) and
    // runs last in BenchmarkManager's processor list, so it's the one most
    // likely to still be mid-run -- and therefore missing from `results` --
    // when a user, seeing the faster models already finished, taps its Play
    // button. That produced a silent no-op. Each Play button is now disabled
    // until its own model's result exists and actually has a file on disk.
    private func hasPlayableOutput(_ type: ModelType) -> Bool {
        guard let result = benchmarkManager.results[type] else { return false }
        return !result.outputFilePath.isEmpty
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    Text("VibeTalk Audio Lab").font(.largeTitle).bold()
                    Button(audioManager.isRecording ? "Stop Recording" : "Start Recording") {
                        audioManager.isRecording ? audioManager.stopRecording() : audioManager.startRecording()
                    }
                    .foregroundColor(.white).padding().background(audioManager.isRecording ? Color.red : Color.green).cornerRadius(12)

                    Text("Recorded: \(String(format: "%.1f", audioManager.recordingDuration)) s")

                    Picker("Duration", selection: $audioManager.selectedDuration) {
                        Text("5s").tag(5); Text("10s").tag(10); Text("20s").tag(20); Text("30s").tag(30)
                    }.pickerStyle(.segmented)
                    Picker("Chunk", selection: $audioManager.selectedChunkSize) {
                        Text("20ms").tag(20); Text("40ms").tag(40); Text("60ms").tag(60); Text("100ms").tag(100)
                    }.pickerStyle(.segmented)

                    Text("48 kHz • Mono • Float32 PCM • RNNoise frame = 10 ms")
                        .font(.caption).foregroundColor(.secondary)

                    Button("Run REAL Benchmark") {
                        audioManager.playbackError = nil
                        benchmarkManager.runBenchmark(audioManager: audioManager, processors: [RNNoiseProcessor(), DTLN2Processor(), DeepFilterNet3Processor()])
                    }.buttonStyle(.borderedProminent).disabled(audioManager.originalFilePath.isEmpty || benchmarkManager.isRunning)

                    if benchmarkManager.isRunning {
                        Text("Бенчмарк ещё выполняется — DFNet3 (самая тяжёлая модель) обрабатывается последней, его Play-кнопка станет активна позже остальных.")
                            .font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
                    }

                    HStack {
                        Button("Original") { audioManager.playAudioFile(at: audioManager.originalFilePath) }
                            .disabled(audioManager.originalFilePath.isEmpty)
                        Button("RNNoise") { audioManager.playAudioFile(at: benchmarkManager.results[.rnnoise]?.outputFilePath ?? "") }
                            .disabled(!hasPlayableOutput(.rnnoise))
                    }
                    HStack {
                        Button("DTLN2") { audioManager.playAudioFile(at: benchmarkManager.results[.dtln2]?.outputFilePath ?? "") }
                            .disabled(!hasPlayableOutput(.dtln2))
                        Button("DFNet3") { audioManager.playAudioFile(at: benchmarkManager.results[.dfnet3]?.outputFilePath ?? "") }
                            .disabled(!hasPlayableOutput(.dfnet3))
                    }

                    // FIX: playAudioFile() used to fail silently (console
                    // `print` only). Any failure -- not-ready result, missing
                    // file on disk, engine start failure -- now surfaces here.
                    if let error = audioManager.playbackError {
                        Text(error)
                            .font(.footnote).foregroundColor(.red).multilineTextAlignment(.center)
                    }

                    NavigationLink("Results", destination: ResultsView(benchmarkManager: benchmarkManager))
                        .buttonStyle(.bordered)

                    Text("DTLN2: 16 kHz двухстадийный streaming ONNX. Stage 2 — ваш 2.5 MB файл; Stage 1 подтягивается Codemagic автоматически. DFNet3 использует native runtime. Никаких фиктивных метрик.")
                        .font(.footnote).foregroundColor(.orange).multilineTextAlignment(.center)
                }.padding()
            }
        }
    }
}
