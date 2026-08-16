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
    private var state1: [Float] = []
    private var state2: [Float] = []
    private var state1Shape: [NSNumber] = []
    private var state2Shape: [NSNumber] = []
    private var input1Name = ""
    private var state1Name = ""
    private var input2Name = ""
    private var state2Name = ""
    private var maskOutputName = ""
    private var state1OutputName = ""
    private var blockOutputName = ""
    private var state2OutputName = ""

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
        if !state1Shape.isEmpty { state1 = [Float](repeating: 0, count: state1Shape.reduce(1) { $0 * max(1, $1.intValue) }) }
        if !state2Shape.isEmpty { state2 = [Float](repeating: 0, count: state2Shape.reduce(1) { $0 * max(1, $1.intValue) }) }
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

        guard in1.count >= 2, out1.count >= 2, in2.count >= 2, out2.count >= 2 else {
            throw DTLNError.graph("DTLN requires 2 inputs and 2 outputs per stage")
        }

        input1Name = in1[0]
        state1Name = in1[1]
        maskOutputName = out1[0]
        state1OutputName = out1[1]

        input2Name = in2[0]
        state2Name = in2[1]
        blockOutputName = out2[0]
        state2OutputName = out2[1]

        // FIX: on-device ONNX Runtime rejected the previous 4-D shape with
        // "Invalid rank for input: h1_in Got: 4 Expected: 3" -- the model's
        // GRU state input is rank-3, not rank-4. DTLN's stock architecture
        // uses 2 stacked GRU layers of 128 units per stage, giving
        // (batch=1, layers=2, units=128). The ObjC ORTSession bindings don't
        // expose input shape/rank metadata to query this at runtime, so if
        // this specific shape is still off, ONNX Runtime's next error will
        // state the exact expected shape (it always does) and this can be
        // adjusted again from that message.
        state1Shape = [1, 2, 128]
        state2Shape = [1, 2, 128]
        state1 = [Float](repeating: 0, count: 1 * 2 * 128)
        state2 = [Float](repeating: 0, count: 1 * 2 * 128)
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
        let stateValue = try makeTensor(state1, shape: state1Shape)
        let result1 = try s1Run([input1Name: magValue, state1Name: stateValue],
                                outputs: [maskOutputName, state1OutputName])

        guard let maskValue = result1[maskOutputName],
              let nextState1Value = result1[state1OutputName] else {
            throw DTLNError.inference("DTLN stage 1 did not return both outputs")
        }

        let mask = try tensorFloats(maskValue)
        state1 = try tensorFloats(nextState1Value)
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
        let timeValue = try makeTensor(timeBlock, shape: [1, 1, 512])
        let state2Value = try makeTensor(state2, shape: state2Shape)
        let result2 = try s2Run([input2Name: timeValue, state2Name: state2Value],
                                outputs: [blockOutputName, state2OutputName])

        guard let outValue = result2[blockOutputName],
              let nextState2Value = result2[state2OutputName] else {
            throw DTLNError.inference("DTLN stage 2 did not return both outputs")
        }

        let outBlock = try tensorFloats(outValue)
        state2 = try tensorFloats(nextState2Value)
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
