import Foundation

protocol AudioProcessor {
    var modelName: String { get }
    var isAvailable: Bool { get }
    var status: String { get }
    func process(chunk: Data, sampleRate: Double, channels: UInt32) throws -> Data
    func reset()
}

enum AudioProcessorError: LocalizedError {
    case unavailable(String), unsupportedFormat(String), invalidInput(String), nativeFailure(String)
    var errorDescription: String? { switch self { case .unavailable(let s), .unsupportedFormat(let s), .invalidInput(let s), .nativeFailure(let s): return s } }
}

final class RNNoiseProcessor: AudioProcessor {
    let modelName = "RNNoise"
    private var state: UnsafeMutableRawPointer?
    private let frameSize: Int

    // FIX: previously `status` only ever said "REAL" or a generic
    // "NOT AVAILABLE" with no way to know why vt_rnnoise_create() returned
    // NULL. RNNoiseBridge.c now records the exact failure reason; we read it
    // once at init time (before it can be overwritten by a later call) and
    // surface it the same way DTLN2Processor already does.
    private(set) var initializationError: String?

    var isAvailable: Bool { state != nil }
    var status: String {
        if isAvailable { return "REAL" }
        return initializationError.map { "FAILED: \($0)" } ?? "NOT AVAILABLE"
    }

    init() {
        frameSize = max(1, Int(vt_rnnoise_frame_size()))
        state = vt_rnnoise_create()
        if state == nil {
            if let cMessage = vt_rnnoise_last_error() {
                initializationError = String(cString: cMessage)
            } else {
                initializationError = "vt_rnnoise_create() returned NULL (no diagnostic available)"
            }
        }
    }

    deinit { reset() }

    func reset() {
        if let s = state { vt_rnnoise_destroy(s) }
        state = nil
    }

    func process(chunk: Data, sampleRate: Double, channels: UInt32) throws -> Data {
        guard sampleRate == 48000 else { throw AudioProcessorError.unsupportedFormat("RNNoise requires 48 kHz") }
        guard channels == 1 else { throw AudioProcessorError.unsupportedFormat("RNNoise requires mono") }
        guard let state else { throw AudioProcessorError.unavailable(status) }
        guard chunk.count % 4 == 0 else { throw AudioProcessorError.invalidInput("Float32 PCM required") }
        let n = chunk.count / 4
        var out = [Float](repeating: 0, count: n)
        chunk.withUnsafeBytes { raw in
            guard let p = raw.bindMemory(to: Float.self).baseAddress else { return }
            out.withUnsafeMutableBufferPointer { ob in
                var off = 0
                while off + frameSize <= n {
                    _ = vt_rnnoise_process_frame(state, p.advanced(by: off), ob.baseAddress!.advanced(by: off))
                    off += frameSize
                }
                if off < n { for i in off..<n { ob[i] = p[i] } }
            }
        }
        return out.withUnsafeBytes { Data($0) }
    }
}

final class DeepFilterNet3Processor: AudioProcessor {
    let modelName = "DeepFilterNet3"
    private var state: UnsafeMutableRawPointer?
    private var frameSize = 0

    // FIX: same gap as RNNoise above. vt_df3_create() in the Rust bridge can
    // only return NULL via a caught panic; previously that panic message was
    // discarded inside catch_unwind. lib.rs now records it via a panic hook
    // and exposes it through vt_df3_last_error(), which we read here.
    private(set) var initializationError: String?

    var isAvailable: Bool { state != nil }
    var status: String {
        if isAvailable { return "REAL" }
        return initializationError.map { "FAILED: \($0)" } ?? "NOT AVAILABLE"
    }

    init() {
        state = vt_df3_create(100)
        if let s = state {
            frameSize = Int(vt_df3_frame_length(s))
        } else {
            if let cMessage = vt_df3_last_error() {
                initializationError = String(cString: cMessage)
            } else {
                initializationError = "vt_df3_create() returned NULL (no diagnostic available)"
            }
        }
    }

    deinit { reset() }
    func reset() {
        if let s = state { vt_df3_free(s) }
        state = nil
        frameSize = 0
    }

    func process(chunk: Data, sampleRate: Double, channels: UInt32) throws -> Data {
        guard sampleRate == 48000, channels == 1 else { throw AudioProcessorError.unsupportedFormat("DeepFilterNet requires mono 48 kHz") }
        guard let state else { throw AudioProcessorError.unavailable(status) }
        guard frameSize > 0 else { throw AudioProcessorError.nativeFailure("DFNet3 frame length is zero") }
        let n = chunk.count / 4
        guard n % frameSize == 0 else { throw AudioProcessorError.invalidInput("Chunk must be a multiple of \(frameSize) samples") }
        var out = [Float](repeating: 0, count: n)
        chunk.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: Float.self).baseAddress!
            out.withUnsafeMutableBufferPointer { ob in
                for off in stride(from: 0, to: n, by: frameSize) {
                    let result = vt_df3_process_frame(state, p.advanced(by: off), ob.baseAddress!.advanced(by: off))
                    if result.isNaN, let cMessage = vt_df3_last_error() {
                        // Surface run-time processing failures too, not just init failures.
                        NSLog("DFNet3 process_frame error: \(String(cString: cMessage))")
                    }
                }
            }
        }
        return out.withUnsafeBytes { Data($0) }
    }
}

@inline(__always) func dataToFloatArray(_ data: Data) -> [Float] { guard data.count % 4 == 0 else { return [] }; return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
@inline(__always) func floatArrayToData(_ values: [Float]) -> Data { values.withUnsafeBytes { Data($0) } }

