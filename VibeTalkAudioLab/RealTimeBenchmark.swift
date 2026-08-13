import AVFoundation
import Foundation

class RealTimeBenchmark: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private let inputNode = AVAudioInputNode()
    
    @Published var isRunning = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var ttfa: TimeInterval = 0
    @Published var avgLatency: TimeInterval = 0
    @Published var p95Latency: TimeInterval = 0
    @Published var maxLatency: TimeInterval = 0
    @Published var rtf: Double = 0
    @Published var cpuUsage: Double = 0
    @Published var ramUsage: Double = 0
    
    private var benchmarkStartTime: Date?
    private var streamingProcessor = StreamingAudioProcessor()
    private var processors: [AudioProcessor] = []
    private var timer: Timer?
    
    func startBenchmark(durationSeconds: Int, chunkSizeMs: Int, processors: [AudioProcessor]) {
        guard !isRunning else { return }
        
        self.processors = processors
        isRunning = true
        elapsedTime = 0
        benchmarkStartTime = Date()
        
        // Setup audio session
        setupAudioSession()
        
        // Setup streaming processor
        let inputFormat = inputNode.outputFormat(forBus: 0)
        streamingProcessor.setupStreamingPipeline(processors: processors, inputFormat: inputFormat) { [weak self] success in
            guard let self = self, success else { return }
            
            // Install tap to capture audio in chunks
            let frameCount = AVAudioFrameCount(Float(inputFormat.sampleRate) * Float(chunkSizeMs) / 1000.0)
            self.inputNode.installTap(onBus: 0, bufferSize: frameCount, format: inputFormat) { [weak self] buffer, time in
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let self = self else { return }
                    
                    // Process the chunk with all processors
                    self.streamingProcessor.processChunk(buffer, processors: processors) {
                        // Chunk processing completed
                    }
                }
            }
            
            // Start the audio engine
            do {
                try self.audioEngine.start()
                self.streamingProcessor.startStreaming()
                
                // Start timer for duration
                self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    self.elapsedTime += 1
                    if self.elapsedTime >= Double(durationSeconds) {
                        self.stopBenchmark()
                    }
                }
            } catch {
                print("Failed to start audio engine: \(error)")
                self.stopBenchmark()
            }
        }
    }
    
    func stopBenchmark() {
        guard isRunning else { return }
        
        isRunning = false
        timer?.invalidate()
        timer = nil
        
        // Stop audio processing
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        streamingProcessor.stopStreaming()
        
        // Calculate final metrics
        calculateFinalMetrics()
        
        // Reset for next run
        streamingProcessor.resetMetrics()
    }
    
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
        
        // Connect input node to main mixer
        audioEngine.attach(inputNode)
        audioEngine.connect(inputNode, to: audioEngine.mainMixerNode, format: inputNode.outputFormat(forBus: 0))
    }
    
    private func calculateFinalMetrics() {
        ttfa = streamingProcessor.calculateTTFA()
        avgLatency = streamingProcessor.calculateAvgLatency()
        p95Latency = streamingProcessor.calculateP95Latency()
        maxLatency = streamingProcessor.calculateMaxLatency()
        
        if let startTime = benchmarkStartTime {
            let fullProcessingTime = Date().timeIntervalSince(startTime)
            rtf = fullProcessingTime / elapsedTime
        }
        
        // Simulate CPU and RAM usage (in a real app, these would be measured)
        cpuUsage = Double.random(in: 30...70)  // 30-70% CPU
        ramUsage = Double.random(in: 100...300)  // 100-300 MB RAM
    }
}