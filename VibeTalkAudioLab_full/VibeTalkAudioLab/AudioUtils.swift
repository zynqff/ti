import Foundation
import AVFoundation

class AudioUtils {
    // Convert Float array to Data
    static func floatArrayToData(_ floatArray: [Float]) -> Data {
        let data = Data(bytes: floatArray, count: floatArray.count * MemoryLayout<Float>.size)
        return data
    }
    
    // Convert Data to Float array
    static func dataToFloatArray(_ data: Data) -> [Float] {
        let floats = data.withUnsafeBytes { pointer -> [Float] in
            let floatPointer = pointer.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: floatPointer.baseAddress, count: data.count / MemoryLayout<Float>.size))
        }
        return floats
    }
    
    // Calculate RMS of audio buffer
    static func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let floatData = buffer.floatChannelData else {
            return 0.0
        }
        
        let channelData = floatData[0]
        let frameCount = Int(buffer.frameLength)
        
        var sum: Float = 0.0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        return sqrt(sum / Float(frameCount))
    }
    
    // Convert linear amplitude to dB
    static func linearToDB(_ linear: Float) -> Float {
        return 20.0 * log10(max(linear, 0.0001)) // Avoid log(0)
    }
    
    // Generate test tone
    static func generateTestTone(frequency: Float, duration: TimeInterval, sampleRate: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        
        buffer.frameLength = frameCount
        
        if let floatData = buffer.floatChannelData {
            let channelData = floatData[0]
            let twoPi = Float.pi * 2
            
            for i in 0..<Int(frameCount) {
                let time = Float(i) / Float(sampleRate)
                channelData[i] = sin(twoPi * frequency * time)
            }
        }
        
        return buffer
    }
}