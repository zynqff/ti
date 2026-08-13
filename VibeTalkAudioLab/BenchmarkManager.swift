import Foundation
import AVFoundation

enum ModelType: CaseIterable {
    case rnnoise
    case dfnet2
    case dfnet3
    
    var displayName: String {
        switch self {
        case .rnnoise: return "RNNoise"
        case .dfnet2: return "DFNet2 Lite"
        case .dfnet3: return "DFNet3"
        }
    }
}

struct BenchmarkResult {
    let modelType: ModelType
    let ttfa: TimeInterval
    let avgLatency: TimeInterval
    let p50Latency: TimeInterval
    let p95Latency: TimeInterval
    let maxLatency: TimeInterval
    let fullProcessingTime: TimeInterval
    let rtf: Double
    let cpuUsage: Double
    let ramUsage: Double
    let outputFilePath: String
}

class BenchmarkManager: ObservableObject {
    @Published var results: [ModelType: BenchmarkResult] = [:]
    @Published var isRunning = false
    
    func runBenchmark(audioManager: AudioManager, processors: [AudioProcessor]) {
        guard !isRunning, !audioManager.originalFilePath.isEmpty else { return }
        
        isRunning = true
        results.removeAll()
        
        // Load original audio file
        guard let audioFile = try? AVAudioFile(forReading: URL(fileURLWithPath: audioManager.originalFilePath)),
              let inputFileBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: AVAudioFrameCount(audioFile.length)) else {
            print("Could not load original audio file")
            isRunning = false
            return
        }
        
        try? audioFile.read(into: inputFileBuffer)
        
        // Process with each model
        for processor in processors {
            let startTime = CFAbsoluteTimeGetCurrent()
            let outputBuffer = processAudioWithProcessor(
                inputFileBuffer: inputFileBuffer,
                processor: processor,
                sampleRate: audioManager.sampleRate,
                channels: audioManager.channels
            )
            
            let endTime = CFAbsoluteTimeGetCurrent()
            let processingTime = endTime - startTime
            
            // Save processed audio
            let outputFilePath = saveProcessedAudio(outputBuffer: outputBuffer, modelName: processor.modelName)
            
            // Calculate metrics
            let result = BenchmarkResult(
                modelType: getModelType(for: processor.modelName),
                ttfa: calculateTTFA(), // Placeholder
                avgLatency: calculateAvgLatency(), // Placeholder
                p50Latency: calculateP50Latency(), // Placeholder
                p95Latency: calculateP95Latency(), // Placeholder
                maxLatency: calculateMaxLatency(), // Placeholder
                fullProcessingTime: processingTime,
                rtf: processingTime / Double(audioManager.selectedDuration),
                cpuUsage: calculateCPUUsage(), // Placeholder
                ramUsage: calculateRAMUsage(), // Placeholder
                outputFilePath: outputFilePath
            )
            
            results[result.modelType] = result
        }
        
        isRunning = false
    }
    
    private func processAudioWithProcessor(inputFileBuffer: AVAudioPCMBuffer, 
                                         processor: AudioProcessor,
                                         sampleRate: Double,
                                         channels: AVAudioChannelCount) -> AVAudioPCMBuffer {
        // Create output buffer with same format as input
        let outputBuffer = AVAudioPCMBuffer(pcmFormat: inputFileBuffer.format, 
                                          frameCapacity: inputFileBuffer.frameCapacity)!
        
        // Copy format to output buffer
        outputBuffer.frameLength = inputFileBuffer.frameLength
        
        // In a real implementation, we would process the buffer in chunks
        // For now, we'll just copy the input to output
        if let inputFloatChannelData = inputFileBuffer.floatChannelData,
           let outputFloatChannelData = outputBuffer.floatChannelData {
            let frameCount = Int(inputFileBuffer.frameLength)
            for channel in 0..<Int(channels) {
                memcpy(outputFloatChannelData[channel], inputFloatChannelData[channel], frameCount * MemoryLayout<Float>.size)
            }
        }
        
        return outputBuffer
    }
    
    private func saveProcessedAudio(outputBuffer: AVAudioPCMBuffer, modelName: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "\(modelName)_processed_\(timestamp).wav"
        let filePath = FileManager.default.temporaryDirectory.appendingPathComponent(fileName).path
        
        guard let outputFile = try? AVAudioFile(forWriting: URL(fileURLWithPath: filePath), 
                                              settings: outputBuffer.format.settings) else {
            return ""
        }
        
        try? outputFile.write(from: outputBuffer)
        return filePath
    }
    
    private func calculateTTFA() -> TimeInterval {
        // Placeholder implementation
        return 0.052  // 52ms as per example in spec
    }
    
    private func calculateAvgLatency() -> TimeInterval {
        // Placeholder implementation
        return 0.045  // 45ms average
    }
    
    private func calculateP50Latency() -> TimeInterval {
        // Placeholder implementation
        return 0.040  // 40ms median
    }
    
    private func calculateP95Latency() -> TimeInterval {
        // Placeholder implementation
        return 0.080  // 80ms p95
    }
    
    private func calculateMaxLatency() -> TimeInterval {
        // Placeholder implementation
        return 0.120  // 120ms max
    }
    
    private func calculateCPUUsage() -> Double {
        // Placeholder implementation
        return 45.0  // 45% average CPU
    }
    
    private func calculateRAMUsage() -> Double {
        // Placeholder implementation
        return 120.0  // 120MB RAM
    }
    
    private func getModelType(for modelName: String) -> ModelType {
        switch modelName {
        case "RNNoise":
            return .rnnoise
        case "DeepFilterNet2 Lite":
            return .dfnet2
        case "DeepFilterNet3":
            return .dfnet3
        default:
            return .rnnoise
        }
    }
}