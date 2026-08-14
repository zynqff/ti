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
    let modelName="RNNoise"; private var state:UnsafeMutableRawPointer?; private let frameSize:Int
    var isAvailable:Bool{state != nil}; var status:String{isAvailable ? "REAL" : "NOT AVAILABLE"}
    init(){frameSize=max(1,Int(vt_rnnoise_frame_size()));state=vt_rnnoise_create()}
    deinit{reset()}
    func reset(){if let s=state{vt_rnnoise_destroy(s)};state=nil}
    func process(chunk:Data,sampleRate:Double,channels:UInt32)throws->Data{
        guard sampleRate==48000 else{throw AudioProcessorError.unsupportedFormat("RNNoise requires 48 kHz")}
        guard channels==1 else{throw AudioProcessorError.unsupportedFormat("RNNoise requires mono")}
        guard let state else{throw AudioProcessorError.unavailable("RNNoise state unavailable")}
        guard chunk.count%4==0 else{throw AudioProcessorError.invalidInput("Float32 PCM required")}
        let n=chunk.count/4;var out=[Float](repeating:0,count:n)
        chunk.withUnsafeBytes{raw in
            guard let p=raw.bindMemory(to:Float.self).baseAddress else{return}
            out.withUnsafeMutableBufferPointer{ob in
                var off=0
                while off+frameSize<=n{_ = vt_rnnoise_process_frame(state,p.advanced(by:off),ob.baseAddress!.advanced(by:off));off += frameSize}
                if off<n{for i in off..<n{ob[i]=p[i]}}
            }
        }
        return out.withUnsafeBytes{Data($0)}
    }
}

final class DeepFilterNet3Processor: AudioProcessor {
    let modelName="DeepFilterNet3";private var state:UnsafeMutableRawPointer?;private var frameSize=0
    var isAvailable:Bool{state != nil};var status:String{isAvailable ? "REAL" : "NOT AVAILABLE"}
    init(){state=vt_df3_create(100);if let s=state{frameSize=Int(vt_df3_frame_length(s))}}
    deinit{reset()};func reset(){if let s=state{vt_df3_free(s)};state=nil;frameSize=0}
    func process(chunk:Data,sampleRate:Double,channels:UInt32)throws->Data{
        guard sampleRate==48000,channels==1 else{throw AudioProcessorError.unsupportedFormat("DeepFilterNet requires mono 48 kHz")}
        guard let state else{throw AudioProcessorError.unavailable("DFNet3 state unavailable")};guard frameSize>0 else{throw AudioProcessorError.nativeFailure("DFNet3 frame length is zero")}
        let n=chunk.count/4;guard n%frameSize==0 else{throw AudioProcessorError.invalidInput("Chunk must be a multiple of \(frameSize) samples")};var out=[Float](repeating:0,count:n)
        chunk.withUnsafeBytes{raw in let p=raw.bindMemory(to:Float.self).baseAddress!;out.withUnsafeMutableBufferPointer{ob in for off in stride(from:0,to:n,by:frameSize){_ = vt_df3_process_frame(state,p.advanced(by:off),ob.baseAddress!.advanced(by:off))}}}
        return out.withUnsafeBytes{Data($0)}
    }
}

@inline(__always) func dataToFloatArray(_ data:Data)->[Float]{guard data.count%4==0 else{return []};return data.withUnsafeBytes{Array($0.bindMemory(to:Float.self))}}
@inline(__always) func floatArrayToData(_ values:[Float])->Data{values.withUnsafeBytes{Data($0)}}
