import SwiftUI

struct BlindTestView: View {
    @StateObject private var audioManager = AudioManager()
    @State private var testSamples: [String: String] = [:] // model name to file path
    @State private var assignments: [String: String] = [:] // A/B/C to model name
    @State private var selectedSample: String?
    @State private var userRating: Int = 0
    @State private var revealed = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Blind A/B/C Test")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Listen to the samples and choose which one sounds best")
                .multilineTextAlignment(.center)
            
            // Assign random letters to models
            Button("Generate New Test") {
                generateTest()
            }
            .buttonStyle(.borderedProminent)
            
            // Play buttons for A, B, C
            HStack(spacing: 20) {
                ForEach(["A", "B", "C"], id: \.self) { letter in
                    VStack {
                        Text(letter)
                            .font(.title2)
                            .frame(width: 50, height: 50)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(25)
                        
                        Button("Play") {
                            if let filePath = testSamples[assignments[letter] ?? ""] {
                                audioManager.playAudioFile(at: filePath)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            // User rating
            if !revealed {
                VStack {
                    Text("Which sample sounds best?")
                        .font(.headline)
                    
                    Picker("", selection: $selectedSample) {
                        Text("A").tag("A")
                        Text("B").tag("B")
                        Text("C").tag("C")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            
            // Reveal button
            if selectedSample != nil && !revealed {
                Button("Reveal Assignments") {
                    revealed = true
                }
                .buttonStyle(.borderedProminent)
            }
            
            // Show results if revealed
            if revealed {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Test Results:")
                        .font(.headline)
                    
                    ForEach(["A", "B", "C"], id: \.self) { letter in
                        if let modelName = assignments[letter] {
                            Text("\(letter) = \(modelName)")
                        }
                    }
                    
                    Text("Your choice: \(selectedSample ?? "None")")
                        .fontWeight(.bold)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            generateTest()
        }
    }
    
    private func generateTest() {
        // In a real implementation, this would load actual processed samples
        // For now, we'll simulate with placeholder file paths
        testSamples = [
            "RNNoise": "/path/to/rnnoise_sample.wav",
            "DTLN2": "/path/to/dtln2_sample.wav",
            "DeepFilterNet3": "/path/to/dfnet3_sample.wav"
        ]
        
        // Randomly assign models to A/B/C
        let models = Array(testSamples.keys).shuffled()
        assignments["A"] = models[safe: 0]
        assignments["B"] = models[safe: 1]
        assignments["C"] = models[safe: 2]
        
        selectedSample = nil
        revealed = false
    }
}

// Extension to safely access array elements
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}