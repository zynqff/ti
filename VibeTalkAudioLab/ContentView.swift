import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var benchmarkManager = BenchmarkManager()

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
                        benchmarkManager.runBenchmark(audioManager: audioManager, processors: [RNNoiseProcessor(), DTLN2Processor(), DeepFilterNet3Processor()])
                    }.buttonStyle(.borderedProminent).disabled(audioManager.originalFilePath.isEmpty || benchmarkManager.isRunning)

                    HStack {
                        Button("Original") { audioManager.playAudioFile(at: audioManager.originalFilePath) }
                        Button("RNNoise") { audioManager.playAudioFile(at: benchmarkManager.results[.rnnoise]?.outputFilePath ?? "") }
                    }
                    HStack {
                        Button("DTLN2") { audioManager.playAudioFile(at: benchmarkManager.results[.dtln2]?.outputFilePath ?? "") }
                        Button("DFNet3") { audioManager.playAudioFile(at: benchmarkManager.results[.dfnet3]?.outputFilePath ?? "") }
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
