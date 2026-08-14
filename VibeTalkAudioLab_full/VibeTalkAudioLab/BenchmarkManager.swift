import Foundation
import AVFoundation
import UIKit
import Darwin

struct BenchmarkResult {
    let modelType: ModelType
    let available: Bool
    let status: String
    let ttfa: TimeInterval
    let avgLatency: TimeInterval
    let p50Latency: TimeInterval
    let p95Latency: TimeInterval
    let maxLatency: TimeInterval
    let fullProcessingTime: TimeInterval
    let rtf: Double
    let cpuUsage: Double
    let ramUsage: Double
    let processedChunks: Int
    let totalChunks: Int
    let droppedChunks: Int
    let outputFilePath: String
    let errorMessage: String?
}

enum ModelType: CaseIterable, Hashable {
    case rnnoise, dtln2, dfnet3
    var displayName: String {
        switch self { case .rnnoise: return "RNNoise"; case .dtln2: return "DTLN2"; case .dfnet3: return "DFNet3" }
    }
}

private struct ProcessSnapshot {
    let cpuSeconds: Double
    let residentBytes: UInt64
}

private enum ProcessMetrics {
    static func snapshot() -> ProcessSnapshot {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        var cpuSeconds = 0.0
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        if result == KERN_SUCCESS, let threadList {
            for i in 0..<Int(threadCount) {
                var ti = thread_basic_info_data_t()
                var c = mach_msg_type_number_t(THREAD_BASIC_INFO_COUNT)
                let kr = withUnsafeMutablePointer(to: &ti) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: Int(c)) {
                        thread_info(threadList[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &c)
                    }
                }
                if kr == KERN_SUCCESS {
                    cpuSeconds += Double(ti.user_time.seconds) + Double(ti.user_time.microseconds) / 1_000_000.0
                    cpuSeconds += Double(ti.system_time.seconds) + Double(ti.system_time.microseconds) / 1_000_000.0
                }
                mach_port_deallocate(mach_task_self_, threadList[i])
            }
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)), vm_size_t(Int(threadCount) * MemoryLayout<thread_act_t>.size))
        }

        let resident = vmResult == KERN_SUCCESS ? UInt64(info.resident_size) : 0
        return ProcessSnapshot(cpuSeconds: cpuSeconds, residentBytes: resident)
    }
}

final class BenchmarkManager: ObservableObject {
    @Published var results: [ModelType: BenchmarkResult] = [:]
    @Published var isRunning = false
    @Published var lastError: String?

    func runBenchmark(audioManager: AudioManager, processors: [AudioProcessor]) {
        guard !isRunning else { return }
        guard !audioManager.originalFilePath.isEmpty else { lastError = "Сначала запишите аудио."; return }
        isRunning = true
        lastError = nil
        results.removeAll()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { DispatchQueue.main.async { self?.isRunning = false } }
            guard let audioFile = try? AVAudioFile(forReading: URL(fileURLWithPath: audioManager.originalFilePath)) else {
                DispatchQueue.main.async { self?.lastError = "Не удалось открыть Original WAV." }
                return
            }
            guard let input = try? Self.readFloatMono(file: audioFile) else {
                DispatchQueue.main.async { self?.lastError = "Original должен быть mono Float32 PCM." }
                return
            }

            let sampleRate = audioFile.processingFormat.sampleRate
            let duration = Double(input.count) / sampleRate
            let chunkFrames = max(1, Int(sampleRate * Double(audioManager.selectedChunkSize) / 1000.0))

            for processor in processors {
                let result = Self.runOne(processor: processor, input: input, sampleRate: sampleRate, chunkFrames: chunkFrames, duration: duration)
                DispatchQueue.main.async { self?.results[Self.modelType(for: processor)] = result }
            }
        }
    }

    private static func runOne(processor: AudioProcessor, input: [Float], sampleRate: Double, chunkFrames: Int, duration: Double) -> BenchmarkResult {
        processor.reset()
        guard processor.isAvailable else {
            return BenchmarkResult(modelType: modelType(for: processor), available: false, status: processor.status,
                                    ttfa: 0, avgLatency: 0, p50Latency: 0, p95Latency: 0, maxLatency: 0,
                                    fullProcessingTime: 0, rtf: 0, cpuUsage: 0, ramUsage: 0,
                                    processedChunks: 0, totalChunks: Int(ceil(Double(input.count) / Double(chunkFrames))), droppedChunks: 0,
                                    outputFilePath: "", errorMessage: processor.status)
        }

        var output = [Float]()
        output.reserveCapacity(input.count)
        var latencies: [TimeInterval] = []
        let totalChunks = Int(ceil(Double(input.count) / Double(chunkFrames)))
        var firstOutputTime: TimeInterval?
        var errorMessage: String?

        let before = ProcessMetrics.snapshot()
        let wallStart = CFAbsoluteTimeGetCurrent()
        for chunkIndex in 0..<totalChunks {
            let start = CFAbsoluteTimeGetCurrent()
            let lo = chunkIndex * chunkFrames
            let hi = min(input.count, lo + chunkFrames)
            let chunk = floatArrayToData(Array(input[lo..<hi]))
            do {
                let processed = try processor.process(chunk: chunk, sampleRate: sampleRate, channels: 1)
                let values = dataToFloatArray(processed)
                if firstOutputTime == nil && !values.isEmpty { firstOutputTime = CFAbsoluteTimeGetCurrent() - wallStart }
                output.append(contentsOf: values)
            } catch {
                errorMessage = error.localizedDescription
                break
            }
            latencies.append(CFAbsoluteTimeGetCurrent() - start)
        }
        let wall = CFAbsoluteTimeGetCurrent() - wallStart
        let after = ProcessMetrics.snapshot()

        guard errorMessage == nil else {
            return BenchmarkResult(modelType: modelType(for: processor), available: true, status: "FAILED", ttfa: 0,
                                    avgLatency: 0, p50Latency: 0, p95Latency: 0, maxLatency: 0, fullProcessingTime: wall,
                                    rtf: duration > 0 ? wall / duration : 0,
                                    cpuUsage: duration > 0 ? max(0, (after.cpuSeconds - before.cpuSeconds) / wall * 100.0) : 0,
                                    ramUsage: Double(after.residentBytes) / 1_048_576.0,
                                    processedChunks: latencies.count, totalChunks: totalChunks, droppedChunks: 0,
                                    outputFilePath: "", errorMessage: errorMessage)
        }

        let outputPath = saveWAV(samples: output, sampleRate: sampleRate, modelName: processor.modelName)
        let sorted = latencies.sorted()
        let avg = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        let p50 = percentile(sorted, 0.50)
        let p95 = percentile(sorted, 0.95)
        let cpu = wall > 0 ? max(0, (after.cpuSeconds - before.cpuSeconds) / wall * 100.0) : 0

        return BenchmarkResult(modelType: modelType(for: processor), available: true, status: "REAL",
                               ttfa: firstOutputTime ?? 0, avgLatency: avg, p50Latency: p50, p95Latency: p95,
                               maxLatency: latencies.max() ?? 0, fullProcessingTime: wall,
                               rtf: duration > 0 ? wall / duration : 0, cpuUsage: cpu,
                               ramUsage: Double(after.residentBytes) / 1_048_576.0,
                               processedChunks: latencies.count, totalChunks: totalChunks, droppedChunks: 0,
                               outputFilePath: outputPath, errorMessage: nil)
    }

    private static func readFloatMono(file: AVAudioFile) throws -> [Float] {
        guard file.processingFormat.channelCount == 1, file.processingFormat.isStandard else {
            throw AudioProcessorError.unsupportedFormat("Benchmark requires mono standard Float32 PCM")
        }
        let capacity = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else { throw AudioProcessorError.invalidInput("Buffer allocation failed") }
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData?[0] else { throw AudioProcessorError.invalidInput("Float channel data unavailable") }
        return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }

    private static func saveWAV(samples: [Float], sampleRate: Double, modelName: String) -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(modelName.replacingOccurrences(of: " ", with: "_"))_processed_\(UUID().uuidString).wav")
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return "" }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let dst = buffer.floatChannelData?[0] { samples.withUnsafeBufferPointer { dst.update(from: $0.baseAddress!, count: samples.count) } }
        do { let f = try AVAudioFile(forWriting: url, settings: format.settings); try f.write(from: buffer); return url.path } catch { return "" }
    }

    private static func percentile(_ sorted: [TimeInterval], _ p: Double) -> TimeInterval {
        guard !sorted.isEmpty else { return 0 }
        let idx = min(sorted.count - 1, max(0, Int(ceil(p * Double(sorted.count))) - 1))
        return sorted[idx]
    }

    private static func modelType(for processor: AudioProcessor) -> ModelType {
        switch processor.modelName { case "RNNoise": return .rnnoise; case "DTLN2": return .dtln2; default: return .dfnet3 }
    }
}
