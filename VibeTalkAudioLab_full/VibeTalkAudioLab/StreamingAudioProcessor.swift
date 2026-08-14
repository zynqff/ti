import AVFoundation
import Foundation

class StreamingAudioProcessor: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private let mixerNode = AVAudioMixerNode()
    private var processorNodes: [AVAudioPlayerNode] = []
    private var outputNodes: [AVAudioPlayerNode] = []
    
    // Metrics
    private var startTime: CFTimeInterval?
    private var firstChunkProcessTime: CFTimeInterval?
    private var chunkProcessTimes: [CFTimeInterval] = []
    private var totalChunksProcessed = 0
    
    func setupStreamingPipeline(processors: [AudioProcessor], 
                              inputFormat: AVAudioFormat,
                              completion: @escaping (Bool) -> Void) {
        // Clear previous nodes
        processorNodes.forEach { audioEngine.detach($0) }
        outputNodes.forEach { audioEngine.detach($0) }
        processorNodes.removeAll()
        outputNodes.removeAll()
        
        // Create a node for each processor
        for processor in processors {
            let processorNode = AVAudioPlayerNode()
            let outputNode = AVAudioPlayerNode()
            
            audioEngine.attach(processorNode)
            audioEngine.attach(outputNode)
            
            // Connect processor to output
            audioEngine.connect(processorNode, to: outputNode, format: inputFormat)
            audioEngine.connect(outputNode, to: audioEngine.mainMixerNode, format: inputFormat)
            
            processorNodes.append(processorNode)
            outputNodes.append(outputNode)
        }
        
        // Prepare the audio engine
        do {
            try audioEngine.prepare()
            completion(true)
        } catch {
            print("Failed to prepare audio engine: \(error)")
            completion(false)
        }
    }
    
    func startStreaming() {
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    func stopStreaming() {
        audioEngine.stop()
    }
    
    func processChunk(_ buffer: AVAudioPCMBuffer, 
                     processors: [AudioProcessor],
                     completionHandler: @escaping () -> Void) {
        totalChunksProcessed += 1
        let chunkStartTime = CFAbsoluteTimeGetCurrent()
        
        // Record start time for TTFA calculation
        if startTime == nil {
            startTime = chunkStartTime
        }
        
        // Process the same buffer with each processor independently
        for i in 0..<processors.count {
            guard i < processorNodes.count else { continue }
            
            // Clone the buffer for this processor
            let clonedBuffer = cloneBuffer(buffer)
            
            // Process asynchronously
            DispatchQueue.global(qos: .userInitiated).async {
                let processedData = processors[i].process(
                    chunk: self.bufferToData(clonedBuffer),
                    sampleRate: clonedBuffer.format.sampleRate,
                    channels: clonedBuffer.format.channelCount
                )
                
                // Convert processed data back to buffer
                if let processedBuffer = self.dataToBuffer(processedData, format: clonedBuffer.format) {
                    DispatchQueue.main.async {
                        self.processorNodes[i].scheduleBuffer(processedBuffer) { [weak self] in
                            // Record when this chunk was processed
                            let chunkEndTime = CFAbsoluteTimeGetCurrent()
                            let processTime = chunkEndTime - chunkStartTime
                            
                            self?.chunkProcessTimes.append(processTime)
                            
                            // Record first chunk process time for TTFA
                            if self?.firstChunkProcessTime == nil {
                                self?.firstChunkProcessTime = chunkEndTime
                            }
                        }
                    }
                }
            }
        }
        
        completionHandler()
    }
    
    private func cloneBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let clonedBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity)!
        clonedBuffer.frameLength = buffer.frameLength
        
        if let srcFloatData = buffer.floatChannelData,
           let dstFloatData = clonedBuffer.floatChannelData {
            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            
            for channel in 0..<channelCount {
                memcpy(dstFloatData[channel], srcFloatData[channel], frameCount * MemoryLayout<Float>.size)
            }
        }
        
        return clonedBuffer
    }
    
    private func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let floatData = buffer.floatChannelData else {
            return Data()
        }
        
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // For simplicity, we'll take the first channel data
        // In a real multi-channel implementation, you'd handle all channels
        let channelData = floatData[0]
        
        return Data(bytes: channelData, count: frameCount * MemoryLayout<Float>.size)
    }
    
    private func dataToBuffer(_ data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard data.count % MemoryLayout<Float>.size == 0 else { return nil }
        
        let frameCount = data.count / MemoryLayout<Float>.size
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        if let floatData = buffer.floatChannelData {
            _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: floatData[0], count: frameCount))
        }
        
        return buffer
    }
    
    // MARK: - Metrics Calculation
    
    func calculateTTFA() -> TimeInterval {
        guard let start = startTime, let firstProcessed = firstChunkProcessTime else {
            return 0
        }
        return firstProcessed - start
    }
    
    func calculateAvgLatency() -> TimeInterval {
        guard !chunkProcessTimes.isEmpty else { return 0 }
        let sum = chunkProcessTimes.reduce(0, +)
        return sum / Double(chunkProcessTimes.count)
    }
    
    func calculateP50Latency() -> TimeInterval {
        let sortedTimes = chunkProcessTimes.sorted()
        guard !sortedTimes.isEmpty else { return 0 }
        let index = Int(Double(sortedTimes.count) * 0.5)
        return sortedTimes[min(index, sortedTimes.count - 1)]
    }
    
    func calculateP95Latency() -> TimeInterval {
        let sortedTimes = chunkProcessTimes.sorted()
        guard !sortedTimes.isEmpty else { return 0 }
        let index = Int(Double(sortedTimes.count) * 0.95)
        return sortedTimes[min(index, sortedTimes.count - 1)]
    }
    
    func calculateMaxLatency() -> TimeInterval {
        return chunkProcessTimes.max() ?? 0
    }
    
    func getTotalChunksProcessed() -> Int {
        return totalChunksProcessed
    }
    
    func resetMetrics() {
        startTime = nil
        firstChunkProcessTime = nil
        chunkProcessTimes.removeAll()
        totalChunksProcessed = 0
    }
}