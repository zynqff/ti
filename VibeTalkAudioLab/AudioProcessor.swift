import Foundation

protocol AudioProcessor {
    var modelName: String { get }
    var isAvailable: Bool { get }
    var status: String { get }
    func process(chunk: Data, sampleRate: Double, channels: UInt32) throws -> Data
    func reset()
    // FIX #9: DFNet3 buffers samples internally until it has a full 480-sample
    // frame (see pendingInput below), so the last, shorter-than-one-frame tail
    // of a recording was silently held forever and never emitted -- heard as
    // eaten word endings, independent of the configured chunk size. flush()
    // gives a processor a chance to emit that zero-padded tail once the
    // caller has no more input coming. Default: nothing to flush.
    func flush() throws -> Data
}

extension AudioProcessor {
    func flush() throws -> Data { Data() }
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

    deinit { destroy() }

    // FIX #5: BenchmarkManager.runOne() calls processor.reset() right
    // before EVERY run, including the first one immediately after a
    // successful init(). The old reset() called vt_rnnoise_destroy() here
    // and never recreated `state`, so RNNoise always reported
    // "NOT AVAILABLE" (isAvailable false, but initializationError still nil
    // because init had actually succeeded) even though it was fully usable.
    // reset() must only clear RNNoise's internal history, not tear down the
    // processor. vt_rnnoise_destroy() is now reserved for deinit only.
    func reset() {
        guard let state else { return }
        if !vt_rnnoise_reset(state) {
            if let cMessage = vt_rnnoise_last_error() {
                initializationError = String(cString: cMessage)
            }
        }
    }

    func destroy() {
        if let s = state { vt_rnnoise_destroy(s) }
        state = nil
    }

    // FIX #8: RNNoise "seemed to not be doing anything" -- confirmed the
    // classic Xiph rnnoise_process_frame() expects samples on the 16-bit
    // PCM scale (~±32768), the convention its RNN was trained on, not
    // normalized -1...1 float32. vt_rnnoise_process_frame() forwards
    // whatever it's given straight through with no scaling, and this
    // Swift side was passing normalized float32 samples directly -- ~32768x
    // too quiet for the model to see anything but near-silence, so its gain
    // estimate barely engaged. Scale up by 32768 on the way in and back down
    // by 1/32768 on the way out; frameSize/off math is unchanged.
    private static let pcmScale: Float = 32768.0

    func process(chunk: Data, sampleRate: Double, channels: UInt32) throws -> Data {
        guard sampleRate == 48000 else { throw AudioProcessorError.unsupportedFormat("RNNoise requires 48 kHz") }
        guard channels == 1 else { throw AudioProcessorError.unsupportedFormat("RNNoise requires mono") }
        guard let state else { throw AudioProcessorError.unavailable(status) }
        guard chunk.count % 4 == 0 else { throw AudioProcessorError.invalidInput("Float32 PCM required") }
        let n = chunk.count / 4
        var out = [Float](repeating: 0, count: n)
        chunk.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: Float.self).baseAddress else { return }
            // Scratch buffers on the PCM scale RNNoise expects.
            var scaledIn = [Float](repeating: 0, count: n)
            for i in 0..<n { scaledIn[i] = src[i] * Self.pcmScale }
            var scaledOut = [Float](repeating: 0, count: n)
            scaledIn.withUnsafeBufferPointer { ib in
                scaledOut.withUnsafeMutableBufferPointer { ob in
                    var off = 0
                    while off + frameSize <= n {
                        _ = vt_rnnoise_process_frame(state, ib.baseAddress!.advanced(by: off), ob.baseAddress!.advanced(by: off))
                        off += frameSize
                    }
                    if off < n { for i in off..<n { ob[i] = ib[i] } }
                }
            }
            out.withUnsafeMutableBufferPointer { ob in
                for i in 0..<n { ob[i] = scaledOut[i] / Self.pcmScale }
            }
        }
        return out.withUnsafeBytes { Data($0) }
    }
}

final class DeepFilterNet3Processor: AudioProcessor {
    let modelName = "DeepFilterNet3"
    private var state: UnsafeMutableRawPointer?
    private var frameSize = 0
    // FIX #7: device reported "Chunk must be a multiple of 480 samples" on
    // the final chunk only (494/495 succeeded). DFNet3's native frame size
    // is fixed at 480 samples, but the benchmark's last chunk is whatever
    // is left over at the end of the file, which is essentially never an
    // exact multiple of 480. Buffer samples across calls (same pattern as
    // DTLN2Processor's pendingInput48k) so every call to vt_df3_process_frame
    // still gets an exact 480-sample frame; any leftover shorter than one
    // frame at the very end of the file is simply carried forward and never
    // needs to satisfy the "multiple of frameSize" requirement on its own.
    private var pendingInput: [Float] = []

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

    deinit { destroy() }

    // FIX #5: same bug pattern as RNNoiseProcessor above.
    // BenchmarkManager.runOne() calls processor.reset() right before EVERY
    // run, including the very first one right after a successful init().
    // The old reset() called vt_df3_free() here and never recreated
    // `state`, so DFNet3 always reported "NOT AVAILABLE" even though init
    // had actually succeeded. vt_df3_reset() already exists in the Rust
    // bridge for exactly this purpose (reinitialize in place, no free) --
    // it just wasn't being called. vt_df3_free() is now reserved for
    // destroy()/deinit only.
    func reset() {
        guard let state else { return }
        vt_df3_reset(state)
        pendingInput.removeAll(keepingCapacity: true)
        // vt_df3_reset() never invalidates `state`, but it can still record
        // a failure reason (e.g. re-init failed) via vt_df3_last_error();
        // surface it for diagnostics without touching availability.
        if let cMessage = vt_df3_last_error() {
            initializationError = String(cString: cMessage)
        }
    }

    func destroy() {
        if let s = state { vt_df3_free(s) }
        state = nil
        frameSize = 0
    }

    func process(chunk: Data, sampleRate: Double, channels: UInt32) throws -> Data {
        guard sampleRate == 48000, channels == 1 else { throw AudioProcessorError.unsupportedFormat("DeepFilterNet requires mono 48 kHz") }
        guard let state else { throw AudioProcessorError.unavailable(status) }
        guard frameSize > 0 else { throw AudioProcessorError.nativeFailure("DFNet3 frame length is zero") }

        pendingInput.append(contentsOf: dataToFloatArray(chunk))

        let framesAvailable = pendingInput.count / frameSize
        guard framesAvailable > 0 else { return Data() }

        let n = framesAvailable * frameSize
        var out = [Float](repeating: 0, count: n)
        pendingInput.withUnsafeBufferPointer { pb in
            let p = pb.baseAddress!
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
        pendingInput.removeFirst(n)
        return out.withUnsafeBytes { Data($0) }
    }

    // FIX #9: emits the final < frameSize leftover (zero-padded up to
    // frameSize for the model call, then trimmed back down to the real
    // leftover length so we don't invent extra audio) instead of losing it.
    func flush() throws -> Data {
        guard let state, !pendingInput.isEmpty else { return Data() }
        let leftover = pendingInput.count
        var frame = pendingInput
        frame.append(contentsOf: repeatElement(0, count: frameSize - leftover))
        var out = [Float](repeating: 0, count: frameSize)
        frame.withUnsafeBufferPointer { ib in
            out.withUnsafeMutableBufferPointer { ob in
                let result = vt_df3_process_frame(state, ib.baseAddress!, ob.baseAddress!)
                if result.isNaN, let cMessage = vt_df3_last_error() {
                    NSLog("DFNet3 flush process_frame error: \(String(cString: cMessage))")
                }
            }
        }
        pendingInput.removeAll(keepingCapacity: true)
        return Array(out.prefix(leftover)).withUnsafeBytes { Data($0) }
    }
}

@inline(__always) func dataToFloatArray(_ data: Data) -> [Float] { guard data.count % 4 == 0 else { return [] }; return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
@inline(__always) func floatArrayToData(_ values: [Float]) -> Data { values.withUnsafeBytes { Data($0) } }
