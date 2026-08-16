import Foundation
import AVFoundation
import OnnxRuntimeBindings

/// Real-time DTLN ONNX runner based on the reference two-stage streaming graph.
/// The reference implementation uses 16 kHz audio, block_len=512 and block_shift=128.
final class DTLN2Processor: AudioProcessor {
    let modelName = "DTLN2"
    private let modelRate: Double = 16_000
    private let inputRate: Double = 48_000
    private let blockLength = 512
    private let blockShift = 128

    private var env: ORTEnv?
    private var session1: ORTSession?
    private var session2: ORTSession?

    // FIX #3: device reported "Missing Input: c1_in" -- this model is an
    // LSTM, not a GRU, and exposes hidden (h) and cell (c) state as two
    // SEPARATE inputs per stage, not one combined tensor. Rather than keep
    // guessing exact input counts/names, every input beyond the first
    // (the audio/spectrum input) is now treated generically as "some state
    // tensor that must be round-tripped every frame", keyed by its own name.
    // This covers h+c today and would also cover a 3rd/4th state tensor
    // without another guess-and-fail round.
    private var input1Name = ""
    private var maskOutputName = ""
    private var stateNames1: [String] = []
    private var stateOutputNames1: [String] = []
    private var states1: [String: [Float]] = [:]
    private var stateShapes1: [String: [NSNumber]] = [:]
    // FIX #4: device reported "DTLN stage 1 has 4 state input(s) but 1 state
    // output(s) -- can't pair them up by position". Inspecting the model
    // confirmed each stage really does take 4 separate state inputs
    // (h1_in, c1_in, h2_in, c2_in) but returns them STACKED into a single
    // output tensor of shape (4, 1, 128) rather than as 4 separate named
    // outputs. When this stacked layout is detected, stateOutputNames1
    // holds that one name and stackedStateOutput1 is set so the runner
    // knows to split it back into per-name slices after every inference.
    private var stackedStateOutput1: String?

    private var input2Name = ""
    private var blockOutputName = ""
    private var stateNames2: [String] = []
    private var stateOutputNames2: [String] = []
    private var states2: [String: [Float]] = [:]
    private var stateShapes2: [String: [NSNumber]] = [:]
    private var stackedStateOutput2: String?

    private var inputBuffer = [Float](repeating: 0, count: 512)
    private var outputBuffer = [Float](repeating: 0, count: 512)
    private var pendingOutput16k: [Float] = []
    private var pendingInput48k: [Float] = []
    private var pendingOutput48k: [Float] = []

    private(set) var initializationError: String?

    var isAvailable: Bool {
        session1 != nil && session2 != nil && initializationError == nil
    }

    var status: String {
        if isAvailable { return "REAL" }
        return initializationError.map { "FAILED: \($0)" } ?? "NOT AVAILABLE"
    }

    init() {
        do {
            // FIX: dtln1.onnx / dtln2.onnx live inside the "Models" folder reference
            // (blue folder in Xcode -> preserves directory structure in the bundle:
            // VibeTalkAudioLab.app/Models/dtln1.onnx). Bundle.main.path(forResource:ofType:)
            // only searches the bundle's TOP LEVEL by default, so without `inDirectory:`
            // it always returned nil here, even though the file was actually present.
            guard let p1 = Bundle.main.path(forResource: "dtln1", ofType: "onnx", inDirectory: "Models") else {
                throw DTLNError.modelMissing("dtln1.onnx (looked in bundle root and Models/)")
            }
            guard let p2 = Bundle.main.path(forResource: "dtln2", ofType: "onnx", inDirectory: "Models") else {
                throw DTLNError.modelMissing("dtln2.onnx (looked in bundle root and Models/)")
            }

            let e = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
            let options = try ORTSessionOptions()
            try options.setIntraOpNumThreads(1)
            self.env = e
            self.session1 = try ORTSession(env: e, modelPath: p1, sessionOptions: options)
            self.session2 = try ORTSession(env: e, modelPath: p2, sessionOptions: options)

            try configureSessions()
            reset()
        } catch {
            initializationError = error.localizedDescription
            session1 = nil
            session2 = nil
        }
    }

    deinit {
        reset()
    }

    func reset() {
        inputBuffer = [Float](repeating: 0, count: blockLength)
        outputBuffer = [Float](repeating: 0, count: blockLength)
        pendingOutput16k.removeAll(keepingCapacity: true)
        pendingInput48k.removeAll(keepingCapacity: true)
        pendingOutput48k.removeAll(keepingCapacity: true)
        for name in stateNames1 {
            let shape = stateShapes1[name] ?? [1, 1, 128]
            states1[name] = [Float](repeating: 0, count: shape.reduce(1) { $0 * max(1, $1.intValue) })
        }
        for name in stateNames2 {
            let shape = stateShapes2[name] ?? [1, 1, 128]
            states2[name] = [Float](repeating: 0, count: shape.reduce(1) { $0 * max(1, $1.intValue) })
        }
    }

    func process(chunk: Data, sampleRate: Double, channels: UInt32) throws -> Data {
        guard sampleRate == inputRate else {
            throw AudioProcessorError.unsupportedFormat("DTLN2 test path expects 48 kHz input")
        }
        guard channels == 1 else {
            throw AudioProcessorError.unsupportedFormat("DTLN2 requires mono input")
        }
        guard isAvailable else {
            throw AudioProcessorError.unavailable(status)
        }

        let source = dataToFloatArray(chunk)
        guard !source.isEmpty else { return Data() }

        // DTLN is fixed at 16 kHz. The benchmark input is 48 kHz, so use a
        // deterministic 3:1 conversion. The model itself still receives exact
        // 512/128-sample 16 kHz blocks.
        pendingInput48k.append(contentsOf: source)
        while pendingInput48k.count >= 3 {
            // A small 3-sample anti-aliasing FIR. This is deliberately simple
            // and deterministic for the lab; production voice code should use
            // AVAudioConverter/vDSP with a stateful high-quality resampler.
            let y = (pendingInput48k[0] + 2.0 * pendingInput48k[1] + pendingInput48k[2]) * 0.25
            pendingOutput16k.append(y)
            pendingInput48k.removeFirst(3)
        }

        while pendingOutput16k.count >= blockShift {
            let frame = Array(pendingOutput16k.prefix(blockShift))
            pendingOutput16k.removeFirst(blockShift)
            try process16kShift(frame)
        }

        // Convert every newly produced 16 kHz sample back to 48 kHz using
        // linear interpolation. Keep the converter deterministic across chunks.
        let available = pendingOutput48k.count
        let target = max(0, source.count)
        if available > 0 {
            let take = min(target / 3, available)
            if take > 0 {
                let part = Array(pendingOutput48k.prefix(take))
                pendingOutput48k.removeFirst(take)
                let up = upsample3(part)
                return floatArrayToData(up)
            }
        }
        return Data()
    }

    private func configureSessions() throws {
        guard let s1 = session1, let s2 = session2 else {
            throw DTLNError.runtime("ONNX sessions were not created")
        }

        let in1 = try s1.inputNames()
        let out1 = try s1.outputNames()
        let in2 = try s2.inputNames()
        let out2 = try s2.outputNames()

        // Input/output 0 is always the audio/spectrum tensor. Everything
        // after that is a recurrent state tensor. FIX #3: device reported
        // "Missing Input: c1_in" -- this is an LSTM with SEPARATE hidden (h)
        // and cell (c) state inputs per stage, not one combined tensor like
        // a GRU. Rather than keep hardcoding "exactly one state input",
        // every extra input/output beyond index 0 is now handled generically
        // by name, which covers h+c today and any further state tensor
        // without another guess-and-fail round.
        guard in1.count >= 2, out1.count >= 2, in2.count >= 2, out2.count >= 2 else {
            throw DTLNError.graph("DTLN requires a main input plus at least one state input/output per stage")
        }

        input1Name = in1[0]
        maskOutputName = out1[0]
        stateNames1 = Array(in1.dropFirst())
        stateOutputNames1 = Array(out1.dropFirst())
        stackedStateOutput1 = try resolveStackedOutput(
            stateNames: stateNames1, stateOutputNames: stateOutputNames1, stageLabel: "1")

        input2Name = in2[0]
        blockOutputName = out2[0]
        stateNames2 = Array(in2.dropFirst())
        stateOutputNames2 = Array(out2.dropFirst())
        stackedStateOutput2 = try resolveStackedOutput(
            stateNames: stateNames2, stateOutputNames: stateOutputNames2, stageLabel: "2")

        // Confirmed via on-device ONNX Runtime errors: each state tensor is
        // rank-3 with shape (batch=1, layers=1, units=128).
        let singleStateShape: [NSNumber] = [1, 1, 128]
        for name in stateNames1 {
            stateShapes1[name] = singleStateShape
            states1[name] = [Float](repeating: 0, count: 128)
        }
        for name in stateNames2 {
            stateShapes2[name] = singleStateShape
            states2[name] = [Float](repeating: 0, count: 128)
        }
    }

    /// Figures out how a stage's state outputs map onto its state inputs.
    /// - If counts match 1:1, outputs are paired to inputs by position (old behavior).
    /// - If there is exactly ONE state output but MULTIPLE state inputs, the
    ///   model is assumed to stack all states along axis 0 into that single
    ///   output (shape (N, 1, units)), as confirmed on dtln1/dtln2.onnx.
    ///   The returned name marks that output as needing to be split back
    ///   into `stateNames.count` per-name slices after every run.
    /// - Anything else is a genuine graph mismatch we can't safely handle.
    private func resolveStackedOutput(stateNames: [String], stateOutputNames: [String], stageLabel: String) throws -> String? {
        if stateOutputNames.count == stateNames.count {
            return nil
        }
        if stateOutputNames.count == 1, stateNames.count > 1 {
            return stateOutputNames[0]
        }
        throw DTLNError.graph("DTLN stage \(stageLabel) has \(stateNames.count) state input(s) but \(stateOutputNames.count) state output(s) -- can't pair them up by position")
    }

    /// Splits a stacked state tensor (shape (N, 1, units), flattened to
    /// N*units floats) back into per-name state slices of `unitsPerState`
    /// floats each, in the same order as `stateNames`.
    private func splitStackedState(_ flat: [Float], into stateNames: [String], unitsPerState: Int) -> [String: [Float]] {
        var result: [String: [Float]] = [:]
        for (i, name) in stateNames.enumerated() {
            let start = i * unitsPerState
            let end = start + unitsPerState
            guard end <= flat.count else { continue }
            result[name] = Array(flat[start..<end])
        }
        return result
    }

    private func process16kShift(_ shift: [Float]) throws {
        inputBuffer.removeFirst(blockShift)
        inputBuffer.append(contentsOf: shift)

        let spectrum = FFT512.forward(inputBuffer)
        var magnitude = [Float](repeating: 0, count: 257)
        var phase = [Float](repeating: 0, count: 257)

        for k in 0...256 {
            let re = spectrum[k].real
            let im = spectrum[k].imag
            magnitude[k] = hypotf(re, im)
            phase[k] = atan2f(im, re)
        }

        let magValue = try makeTensor(magnitude, shape: [1, 1, 257])
        var inputs1: [String: ORTValue] = [input1Name: magValue]
        for name in stateNames1 {
            inputs1[name] = try makeTensor(states1[name] ?? [], shape: stateShapes1[name] ?? [1, 1, 128])
        }
        let result1 = try s1Run(inputs1, outputs: Set([maskOutputName] + stateOutputNames1))

        guard let maskValue = result1[maskOutputName] else {
            throw DTLNError.inference("DTLN stage 1 did not return \(maskOutputName)")
        }
        if let stackedName = stackedStateOutput1 {
            guard let v = result1[stackedName] else {
                throw DTLNError.inference("DTLN stage 1 did not return state output \(stackedName)")
            }
            let flat = try tensorFloats(v)
            let unitsPerState = stateNames1.isEmpty ? 0 : flat.count / stateNames1.count
            let split = splitStackedState(flat, into: stateNames1, unitsPerState: unitsPerState)
            guard split.count == stateNames1.count else {
                throw DTLNError.inference("DTLN stage 1 stacked state output \(stackedName) had \(flat.count) values, expected \(stateNames1.count) x per-state size")
            }
            states1 = split
        } else {
            for (i, outName) in stateOutputNames1.enumerated() {
                guard let v = result1[outName] else {
                    throw DTLNError.inference("DTLN stage 1 did not return state output \(outName)")
                }
                states1[stateNames1[i]] = try tensorFloats(v)
            }
        }

        let mask = try tensorFloats(maskValue)
        guard mask.count == 257 else {
            throw DTLNError.inference("DTLN stage 1 mask count \(mask.count), expected 257")
        }

        var estimated = [FFT512.C](repeating: FFT512.C(real: 0, imag: 0), count: 512)
        for k in 0...256 {
            let a = magnitude[k] * mask[k]
            estimated[k] = FFT512.C(real: a * cosf(phase[k]), imag: a * sinf(phase[k]))
        }
        for k in 257..<512 {
            let mirror = 512 - k
            estimated[k] = FFT512.C(real: estimated[mirror].real, imag: -estimated[mirror].imag)
        }

        let timeBlock = FFT512.inverse(estimated)
        // FIX #6: device reported "Got invalid dimensions for input: y1 ...
        // index 1 Got 1 Expected 512, index 2 Got 512 Expected 1". dtln2.onnx's
        // y1 input is actually shape (1, 512, 1), not (1, 1, 512) -- axes 1
        // and 2 were swapped.
        let timeValue = try makeTensor(timeBlock, shape: [1, 512, 1])
        var inputs2: [String: ORTValue] = [input2Name: timeValue]
        for name in stateNames2 {
            inputs2[name] = try makeTensor(states2[name] ?? [], shape: stateShapes2[name] ?? [1, 1, 128])
        }
        let result2 = try s2Run(inputs2, outputs: Set([blockOutputName] + stateOutputNames2))

        guard let outValue = result2[blockOutputName] else {
            throw DTLNError.inference("DTLN stage 2 did not return \(blockOutputName)")
        }
        if let stackedName = stackedStateOutput2 {
            guard let v = result2[stackedName] else {
                throw DTLNError.inference("DTLN stage 2 did not return state output \(stackedName)")
            }
            let flat = try tensorFloats(v)
            let unitsPerState = stateNames2.isEmpty ? 0 : flat.count / stateNames2.count
            let split = splitStackedState(flat, into: stateNames2, unitsPerState: unitsPerState)
            guard split.count == stateNames2.count else {
                throw DTLNError.inference("DTLN stage 2 stacked state output \(stackedName) had \(flat.count) values, expected \(stateNames2.count) x per-state size")
            }
            states2 = split
        } else {
            for (i, outName) in stateOutputNames2.enumerated() {
                guard let v = result2[outName] else {
                    throw DTLNError.inference("DTLN stage 2 did not return state output \(outName)")
                }
                states2[stateNames2[i]] = try tensorFloats(v)
            }
        }

        let outBlock = try tensorFloats(outValue)
        guard outBlock.count >= blockLength else {
            throw DTLNError.inference("DTLN stage 2 output has \(outBlock.count), expected >= 512")
        }

        outputBuffer.removeFirst(blockShift)
        outputBuffer.append(contentsOf: repeatElement(0, count: blockShift))
        for i in 0..<blockLength {
            outputBuffer[i] += outBlock[i]
        }
        pendingOutput48k.append(contentsOf: outputBuffer.prefix(blockShift))
    }

    private func s1Run(_ inputs: [String: ORTValue], outputs: Set<String>) throws -> [String: ORTValue] {
        guard let s = session1 else { throw DTLNError.runtime("Stage 1 session unavailable") }
        return try s.run(withInputs: inputs, outputNames: outputs, runOptions: nil)
    }

    private func s2Run(_ inputs: [String: ORTValue], outputs: Set<String>) throws -> [String: ORTValue] {
        guard let s = session2 else { throw DTLNError.runtime("Stage 2 session unavailable") }
        return try s.run(withInputs: inputs, outputNames: outputs, runOptions: nil)
    }

    private func makeTensor(_ values: [Float], shape: [NSNumber]) throws -> ORTValue {
        let data = values.withUnsafeBytes { NSMutableData(bytes: $0.baseAddress!, length: $0.count) }
        return try ORTValue(tensorData: data, elementType: .float, shape: shape)
    }

    private func tensorFloats(_ value: ORTValue) throws -> [Float] {
        let data = try value.tensorData()
        let count = data.length / MemoryLayout<Float>.size
        return (data as Data).withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self).prefix(count))
        }
    }

    private func normalizeShape(_ shape: [NSNumber]) -> [NSNumber] {
        shape.map { $0.intValue > 0 ? $0 : 1 }
    }

    private func downsampleInput(_ source: [Float]) -> [Float] {
        var result: [Float] = []
        result.reserveCapacity(source.count / 3)
        var i = 0
        while i + 2 < source.count {
            result.append((source[i] + 2 * source[i + 1] + source[i + 2]) * 0.25)
            i += 3
        }
        return result
    }

    private func upsample3(_ x: [Float]) -> [Float] {
        guard !x.isEmpty else { return [] }
        var y = [Float](repeating: 0, count: x.count * 3)
        for i in 0..<x.count {
            let a = x[i]
            let b = i + 1 < x.count ? x[i + 1] : a
            y[i * 3] = a
            y[i * 3 + 1] = a + (b - a) / 3
            y[i * 3 + 2] = a + 2 * (b - a) / 3
        }
        return y
    }
}

private enum DTLNError: LocalizedError {
    case modelMissing(String)
    case runtime(String)
    case graph(String)
    case inference(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing(let f): return "DTLN model missing: \(f)"
        case .runtime(let s): return "DTLN runtime: \(s)"
        case .graph(let s): return "DTLN graph: \(s)"
        case .inference(let s): return "DTLN inference: \(s)"
        }
    }
}

/// Minimal radix-2 complex FFT used only for the fixed 512-sample DTLN block.
/// The reference DTLN pipeline uses rFFT/irFFT; this complex implementation
/// produces the same half-spectrum and Hermitian reconstruction.
private enum FFT512 {
    struct C {
        var real: Float
        var imag: Float
    }

    static func forward(_ x: [Float]) -> [C] {
        var a = x.map { C(real: $0, imag: 0) }
        fft(&a, inverse: false)
        return a
    }

    static func inverse(_ x: [C]) -> [Float] {
        var a = x
        fft(&a, inverse: true)
        return a.map(\.real)
    }

    private static func fft(_ a: inout [C], inverse: Bool) {
        let n = a.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j { a.swapAt(i, j) }
        }

        var len = 2
        while len <= n {
            let angle = (inverse ? 2.0 : -2.0) * Float.pi / Float(len)
            let wLen = C(real: cosf(angle), imag: sinf(angle))
            var i = 0
            while i < n {
                var w = C(real: 1, imag: 0)
                for k in 0..<(len / 2) {
                    let u = a[i + k]
                    let v0 = a[i + k + len / 2]
                    let v = C(
                        real: v0.real * w.real - v0.imag * w.imag,
                        imag: v0.real * w.imag + v0.imag * w.real
                    )
                    a[i + k] = C(real: u.real + v.real, imag: u.imag + v.imag)
                    a[i + k + len / 2] = C(real: u.real - v.real, imag: u.imag - v.imag)
                    let nw = C(
                        real: w.real * wLen.real - w.imag * wLen.imag,
                        imag: w.real * wLen.imag + w.imag * wLen.real
                    )
                    w = nw
                }
                i += len
            }
            len <<= 1
        }

        if inverse {
            let scale = 1.0 / Float(n)
            for i in 0..<n {
                a[i].real *= scale
                a[i].imag *= scale
            }
        }
    }
}
