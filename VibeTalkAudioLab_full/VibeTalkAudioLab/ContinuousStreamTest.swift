import Foundation
import AVFoundation

class ContinuousStreamTest: ObservableObject {
    @Published var isRunning = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var avgTTFA: TimeInterval = 0
    @Published var p95Latency: TimeInterval = 0
    @Published var maxLatency: TimeInterval = 0
    @Published var avgCPU: Double = 0
    @Published var peakRAM: Double = 0
    @Published var droppedChunks: Int = 0
    @Published var bufferUnderruns: Int = 0
    
    private var streamTimer: Timer?
    private var startTime: Date?
    private var ttfaMeasurements: [TimeInterval] = []
    private var latencyMeasurements: [TimeInterval] = []
    private var cpuMeasurements: [Double] = []
    private var ramMeasurements: [Double] = []
    
    func startTest(durationMinutes: Int = 20) {
        guard !isRunning else { return }
        
        isRunning = true
        elapsedTime = 0
        startTime = Date()
        
        // Initialize arrays
        ttfaMeasurements = []
        latencyMeasurements = []
        cpuMeasurements = []
        ramMeasurements = []
        
        // Start periodic measurements
        streamTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.elapsedTime += 1
            
            // Collect metrics periodically
            self.collectMetrics()
            
            if self.elapsedTime >= Double(durationMinutes * 60) {
                self.stopTest()
            }
        }
    }
    
    func stopTest() {
        guard isRunning else { return }
        
        isRunning = false
        streamTimer?.invalidate()
        streamTimer = nil
        
        // Calculate final metrics
        calculateFinalMetrics()
    }
    
    private func collectMetrics() {
        // Simulate collecting metrics
        // In a real implementation, this would measure actual performance
        ttfaMeasurements.append(TimeInterval.random(in: 0.020...0.080)) // 20-80ms TTFA
        latencyMeasurements.append(TimeInterval.random(in: 0.025...0.100)) // 25-100ms latency
        cpuMeasurements.append(Double.random(in: 30...60)) // 30-60% CPU
        ramMeasurements.append(Double.random(in: 100...200)) // 100-200MB RAM
        
        // Simulate occasional dropped chunks and buffer underruns
        if Bool.random() && Double.random(in: 0...1) < 0.05 { // 5% chance
            droppedChunks += 1
        }
        
        if Bool.random() && Double.random(in: 0...1) < 0.02 { // 2% chance
            bufferUnderruns += 1
        }
    }
    
    private func calculateFinalMetrics() {
        if !ttfaMeasurements.isEmpty {
            avgTTFA = ttfaMeasurements.reduce(0, +) / Double(ttfaMeasurements.count)
        }
        
        if !latencyMeasurements.isEmpty {
            let sortedLatencies = latencyMeasurements.sorted()
            let p95Index = Int(Double(sortedLatencies.count) * 0.95)
            p95Latency = p95Index < sortedLatencies.count ? sortedLatencies[p95Index] : 0
            
            maxLatency = latencyMeasurements.max() ?? 0
        }
        
        if !cpuMeasurements.isEmpty {
            avgCPU = cpuMeasurements.reduce(0, +) / Double(cpuMeasurements.count)
        }
        
        if !ramMeasurements.isEmpty {
            peakRAM = ramMeasurements.max() ?? 0
        }
    }
}