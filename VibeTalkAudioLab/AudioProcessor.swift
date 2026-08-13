import Foundation

protocol AudioProcessor {
    var modelName: String { get }
    func process(chunk: Data, sampleRate: Double, channels: UInt32) -> Data
    func reset()
}

// Placeholder implementations - in a real app, these would interface with actual models
class RNNoiseProcessor: AudioProcessor {
    let modelName = "RNNoise"
    
    func process(chunk: Data, sampleRate: Double, channels: UInt32) -> Data {
        // Placeholder - in real implementation, this would call RNNoise C library
        return chunk // Return original data for now
    }
    
    func reset() {
        // Reset internal state
    }
}

class DeepFilterNet2Processor: AudioProcessor {
    let modelName = "DeepFilterNet2 Lite"
    
    func process(chunk: Data, sampleRate: Double, channels: UInt32) -> Data {
        // Placeholder - in real implementation, this would call DeepFilterNet2 C library
        return chunk // Return original data for now
    }
    
    func reset() {
        // Reset internal state
    }
}

class DeepFilterNet3Processor: AudioProcessor {
    let modelName = "DeepFilterNet3"
    
    func process(chunk: Data, sampleRate: Double, channels: UInt32) -> Data {
        // Placeholder - in real implementation, this would call DeepFilterNet3 C library
        return chunk // Return original data for now
    }
    
    func reset() {
        // Reset internal state
    }
}