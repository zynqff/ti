import SwiftUI

struct MainBenchmarkView: View {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var benchmarkManager = BenchmarkManager()
    @StateObject private var realTimeBenchmark = RealTimeBenchmark()
    @StateObject private var continuousTest = ContinuousStreamTest()
    @StateObject private var hardwareBenchmark = HardwareBenchmarkManager()
    
    @State private var showingBlindTest = false
    @State private var showingContinuousTest = false
    @State private var showingHardwareComparison = false
    
    var body: some View {
        TabView {
            // Main Controls Tab
            VStack {
                Text("VibeTalk Audio Lab")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
                
                // Recording controls
                GroupBox(label: Label("Recording", systemImage: "mic")) {
                    HStack {
                        Button(action: {
                            if audioManager.isRecording {
                                audioManager.stopRecording()
                            } else {
                                audioManager.startRecording()
                            }
                        }) {
                            HStack {
                                Image(systemName: audioManager.isRecording ? "stop.fill" : "record.circle")
                                    .font(.title2)
                                Text(audioManager.isRecording ? "Stop" : "Start Recording")
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(audioManager.isRecording ? Color.red : Color.green)
                            .cornerRadius(10)
                        }
                        
                        VStack(alignment: .leading) {
                            Text("\(audioManager.recordingDuration.formatted(seconds: 1))s")
                                .font(.headline)
                            Text("/\(audioManager.selectedDuration)s")
                                .font(.caption)
                        }
                    }
                }
                
                // Settings
                GroupBox(label: Label("Settings", systemImage: "gear")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Duration:")
                            Picker("Duration", selection: $audioManager.selectedDuration) {
                                Text("5s").tag(5)
                                Text("10s").tag(10)
                                Text("20s").tag(20)
                                Text("30s").tag(30)
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(maxWidth: 120)
                        }
                        
                        HStack {
                            Text("Chunk Size:")
                            Picker("Chunk Size", selection: $audioManager.selectedChunkSize) {
                                Text("20ms").tag(20)
                                Text("40ms").tag(40)
                                Text("60ms").tag(60)
                                Text("100ms").tag(100)
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(maxWidth: 120)
                        }
                        
                        Text("Sample Rate: \(Int(audioManager.sampleRate)) Hz")
                        Text("Channels: \(audioManager.channels)")
                        Text("Format: PCM 16-bit")
                    }
                }
                
                // Benchmark controls
                GroupBox(label: Label("Benchmark", systemImage: "speedometer")) {
                    VStack(spacing: 10) {
                        Button("Run Single Benchmark") {
                            benchmarkManager.runBenchmark(
                                audioManager: audioManager,
                                processors: [
                                    RNNoiseProcessor(),
                                    DTLN2Processor(),
                                    DeepFilterNet3Processor()
                                ]
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        
                        NavigationLink("View Results", destination: ResultsView(benchmarkManager: benchmarkManager))
                            .buttonStyle(.bordered)
                    }
                }
                
                // Real-time benchmark
                GroupBox(label: Label("Real-time Processing", systemImage: "gauge.with.dots.needle.67percent")) {
                    VStack(spacing: 10) {
                        HStack {
                            Button(realTimeBenchmark.isRunning ? "Stop Real-time Test" : "Start Real-time Test") {
                                if realTimeBenchmark.isRunning {
                                    realTimeBenchmark.stopBenchmark()
                                } else {
                                    realTimeBenchmark.startBenchmark(
                                        durationSeconds: audioManager.selectedDuration,
                                        chunkSizeMs: audioManager.selectedChunkSize,
                                        processors: [
                                            RNNoiseProcessor(),
                                            DTLN2Processor(),
                                            DeepFilterNet3Processor()
                                        ]
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        if realTimeBenchmark.isRunning {
                            VStack {
                                Text("Live Metrics:")
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("TTFA: \(String(format: "%.1f ms", realTimeBenchmark.ttfa * 1000))")
                                        Text("Avg: \(String(format: "%.1f ms", realTimeBenchmark.avgLatency * 1000))")
                                        Text("P95: \(String(format: "%.1f ms", realTimeBenchmark.p95Latency * 1000))")
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing) {
                                        Text("RTF: \(String(format: "%.2f", realTimeBenchmark.rtf))")
                                        Text("CPU: \(String(format: "%.1f%%", realTimeBenchmark.cpuUsage))")
                                        Text("RAM: \(String(format: "%.0f MB", realTimeBenchmark.ramUsage))")
                                    }
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .tabItem {
                Label("Main", systemImage: "waveform")
            }
            
            // Results Tab
            NavigationView {
                ResultsView(benchmarkManager: benchmarkManager)
            }
            .tabItem {
                Label("Results", systemImage: "chart.bar")
            }
            
            // Additional Tests Tab
            VStack {
                Text("Additional Tests")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding()
                
                VStack(spacing: 20) {
                    NavigationLink(destination: BlindTestView()) {
                        HStack {
                            Image(systemName: "ear")
                            Text("Blind A/B Test")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                    }
                    
                    Button("20-min Continuous Test") {
                        continuousTest.startTest(durationMinutes: 20)
                        showingContinuousTest = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
                
                    Button("Hardware Comparison") {
                        hardwareBenchmark.runHardwareComparisonBenchmark()
                        showingHardwareComparison = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(10)
                }
                
                if showingContinuousTest {
                    GroupBox(label: Label("Continuous Test", systemImage: "timer")) {
                        VStack {
                            Text("Elapsed: \(String(format: "%.1f min", continuousTest.elapsedTime / 60))")
                            Text("Avg TTFA: \(String(format: "%.1f ms", continuousTest.avgTTFA * 1000))")
                            Text("P95 Latency: \(String(format: "%.1f ms", continuousTest.p95Latency * 1000))")
                            Text("Max Latency: \(String(format: "%.1f ms", continuousTest.maxLatency * 1000))")
                            Text("Avg CPU: \(String(format: "%.1f%%", continuousTest.avgCPU))")
                            Text("Peak RAM: \(String(format: "%.0f MB", continuousTest.peakRAM))")
                            Text("Dropped Chunks: \(continuousTest.droppedChunks)")
                            
                            Button("Stop Test") {
                                continuousTest.stopTest()
                                showingContinuousTest = false
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                Spacer()
            }
            .tabItem {
                Label("Tests", systemImage: "list.bullet.rectangle.portrait")
            }
        }
    }
}

extension TimeInterval {
    func formatted(seconds places: Int) -> String {
        String(format: "%.\(places)f", self)
    }
}

struct MainBenchmarkView_Previews: PreviewProvider {
    static var previews: some View {
        MainBenchmarkView()
    }
}