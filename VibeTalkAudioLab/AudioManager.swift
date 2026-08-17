import AVFoundation
import Combine

class AudioManager: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    // FIX: playAudioFile() used to only `print()` on failure, so a missing/
    // empty file (e.g. DFNet3's benchmark result not ready yet) looked
    // exactly like a silently-broken Play button. Now surfaced in the UI.
    @Published var playbackError: String?
    
    let sampleRate: Double = 48000
    let channels: AVAudioChannelCount = 1
    let bitDepth: Int = 16
    
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
        playbackError = nil

        // FIX: this used to be a silent `print()`-only early return. Empty
        // path happens whenever the caller reads `results[.model]?.outputFilePath`
        // before that model's benchmark entry exists yet (e.g. DFNet3 is the
        // heaviest/slowest of the three processors and runs last in
        // BenchmarkManager's list, so it's the one most likely to still be
        // mid-run -- and therefore missing from `results` -- when a user taps
        // its Play button). Report it instead of failing invisibly.
        guard !path.isEmpty else {
            playbackError = "Ещё нет обработанного файла для этой модели — дождитесь окончания бенчмарка."
            return
        }
        guard FileManager.default.fileExists(atPath: path) else {
            playbackError = "Файл результата не найден на диске (возможно, запись WAV не удалась)."
            return
        }

        let playerNode = AVAudioPlayerNode()
        let audioEngine = AVAudioEngine()

        guard let audioFile = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else {
            playbackError = "Не удалось открыть аудиофайл для воспроизведения."
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

            // Auto-stop after playback duration. Round up so short clips
            // (< 1s) still get an audible window instead of an immediate
            // `asyncAfter(deadline: .now() + 0)` stop caused by Int64 division
            // truncating toward zero.
            let playbackDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            DispatchQueue.main.asyncAfter(deadline: .now() + max(playbackDuration, 0.1) + 0.1) {
                playerNode.stop()
                audioEngine.detach(playerNode)
            }
        } catch {
            playbackError = "Не удалось запустить воспроизведение: \(error.localizedDescription)"
        }
    }
}
