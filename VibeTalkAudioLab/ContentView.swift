import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var benchmarkManager = BenchmarkManager()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("VibeTalk Audio Lab")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // Recording controls
                HStack {
                    Button(action: {
                        if audioManager.isRecording {
                            audioManager.stopRecording()
                        } else {
                            audioManager.startRecording()
                        }
                    }) {
                        Text(audioManager.isRecording ? "Stop" : "Start Recording")
                            .foregroundColor(.white)
                            .padding()
                            .background(audioManager.isRecording ? Color.red : Color.green)
                            .cornerRadius(10)
                    }
                    
                    Text("\(audioManager.recordingDuration.formatted(seconds: 1))s")
                        .font(.headline)
                }
                
                // Recording settings
                VStack(alignment: .leading, spacing: 10) {
                    Text("Settings:")
                        .font(.headline)
                    
                    Picker("Duration", selection: $audioManager.selectedDuration) {
                        Text("5s").tag(5)
                        Text("10s").tag(10)
                        Text("20s").tag(20)
                        Text("30s").tag(30)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    Picker("Chunk Size", selection: $audioManager.selectedChunkSize) {
                        Text("20ms").tag(20)
                        Text("40ms").tag(40)
                        Text("60ms").tag(60)
                        Text("100ms").tag(100)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    Text("Sample Rate: \(Int(audioManager.sampleRate)) Hz")
                    Text("Channels: \(audioManager.channels)")
                    Text("Format: PCM 16-bit")
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                // Benchmark controls
                VStack(spacing: 10) {
                    Text("Benchmark Controls:")
                        .font(.headline)
                    
                    Button("Run Benchmark") {
                        benchmarkManager.runBenchmark(
                            audioManager: audioManager,
                            processors: [
                                RNNoiseProcessor(),
                                DeepFilterNet2Processor(),
                                DeepFilterNet3Processor()
                            ]
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    
                    NavigationLink("Results", destination: ResultsView(benchmarkManager: benchmarkManager))
                        .buttonStyle(.bordered)
                }
                
                // Playback controls
                VStack(spacing: 10) {
                    Text("Playback:")
                        .font(.headline)
                    
                    HStack {
                        Button("Original") {
                            audioManager.playAudioFile(at: audioManager.originalFilePath)
                        }
                        .buttonStyle(.bordered)
                        
                        Button("RNNoise") {
                            audioManager.playAudioFile(at: benchmarkManager.results[.rnnoise]?.outputFilePath ?? "")
                        }
                        .buttonStyle(.bordered)
                        
                        Button("DFNet2 Lite") {
                            audioManager.playAudioFile(at: benchmarkManager.results[.dfnet2]?.outputFilePath ?? "")
                        }
                        .buttonStyle(.bordered)
                        
                        Button("DFNet3") {
                            audioManager.playAudioFile(at: benchmarkManager.results[.dfnet3]?.outputFilePath ?? "")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .environmentObject(audioManager)
        .environmentObject(benchmarkManager)
    }
}

extension TimeInterval {
    func formatted(seconds places: Int) -> String {
        String(format: "%.\(places)f", self)
    }
}