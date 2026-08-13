import AVFoundation
import Combine

class AudioManager: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    
    let sampleRate: Double = 48000
    let channels: AVAudioChannelCount = 1
    let bitDepth: AVAudioBitPoint = 16
    
    private var audioEngine: AVAudioEngine
    private var inputNode: AVAudioInputNode
    private var recordingTimer: Timer?
    private var startTime: Date?
    
    var selectedDuration: Int = 20
    var selectedChunkSize: Int = 20
    
    var originalFilePath: String = ""
    
    init() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
        
        setupAudioSession()
        setupNodes()
    }
    
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    private func setupNodes() {
        // Nodes are configured when recording starts
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        recordingDuration = 0
        startTime = Date()
        
        // Create a unique filename for this recording
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "original_\(timestamp).wav"
        originalFilePath = FileManager.default.temporaryDirectory.appendingPathComponent(fileName).path
        
        // Configure audio format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Create audio file
        guard let audioFile = try? AVAudioFile(forWriting: URL(fileURLWithPath: originalFilePath), settings: inputFormat.settings) else {
            print("Could not create audio file")
            return
        }
        
        // Install tap on input node to record
        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(sampleRate * Double(selectedChunkSize) / 1000), format: inputFormat) { buffer, time in
            DispatchQueue.global(qos: .userInitiated).async {
                try? audioFile.write(from: buffer)
            }
        }
        
        // Schedule timer to stop recording after selected duration
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.recordingDuration += 1
            if self.recordingDuration >= Double(self.selectedDuration) {
                self.stopRecording()
            }
        }
        
        do {
            try audioEngine.start()
        } catch {
            print("Could not start audio engine: \(error)")
            stopRecording()
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }
    
    func playAudioFile(at path: String) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            print("Audio file does not exist: \(path)")
            return
        }
        
        let playerNode = AVAudioPlayerNode()
        let audioEngine = AVAudioEngine()
        
        guard let audioFile = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else {
            print("Could not open audio file")
            return
        }
        
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFile.processingFormat)
        
        playerNode.scheduleFile(audioFile, at: nil) { [weak self] in
            // Playback finished
        }
        
        do {
            try audioEngine.start()
            playerNode.play()
            
            // Auto-stop after playback duration
            let playbackDuration = audioFile.length / Int64(audioFile.processingFormat.sampleRate)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(playbackDuration)) {
                playerNode.stop()
                audioEngine.detach(playerNode)
            }
        } catch {
            print("Could not start audio playback: \(error)")
        }
    }
}