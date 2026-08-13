import Foundation
import UIKit

struct DeviceInfo {
    let name: String
    let model: String
    let osVersion: String
    let chip: String
    let memory: String
}

struct BenchmarkSummary {
    let deviceInfo: DeviceInfo
    let results: [ModelType: BenchmarkResult]
    
    var formattedCSV: String {
        let header = "Device,Model,Chunk,TTFA,Avg,P95,Full,RTF,CPU,RAM\n"
        
        var rows: [String] = []
        for modelType in ModelType.allCases {
            if let result = results[modelType] {
                let row = "\(deviceInfo.name),\(result.modelType.displayName),20ms,\(String(format: "%.3f", result.ttfa)),\(String(format: "%.3f", result.avgLatency)),\(String(format: "%.3f", result.p95Latency)),\(String(format: "%.3f", result.fullProcessingTime)),\(String(format: "%.2f", result.rtf)),\(String(format: "%.1f", result.cpuUsage)),\(String(format: "%.1f", result.ramUsage))"
                rows.append(row)
            }
        }
        
        return header + rows.joined(separator: "\n")
    }
}

class HardwareBenchmarkManager: ObservableObject {
    @Published var benchmarkSummaries: [BenchmarkSummary] = []
    
    func runHardwareComparisonBenchmark() {
        // Collect device information
        let deviceInfo = DeviceInfo(
            name: UIDevice.current.name,
            model: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion,
            chip: getChipInfo(),
            memory: "\(ProcessInfo.processInfo.physicalMemory / 1024 / 1024) MB"
        )
        
        // In a real implementation, this would run benchmarks across different devices
        // For now, we'll simulate results for both iPhone 12 and iPhone 14 Pro
        
        // Simulate iPhone 12 results
        let iPhone12Results = simulateBenchmarkResults(for: "iPhone 12")
        let iPhone12Summary = BenchmarkSummary(deviceInfo: deviceInfo, results: iPhone12Results)
        
        // Simulate iPhone 14 Pro results
        let iPhone14ProResults = simulateBenchmarkResults(for: "iPhone 14 Pro")
        let iPhone14ProSummary = BenchmarkSummary(deviceInfo: deviceInfo, results: iPhone14ProResults)
        
        benchmarkSummaries = [iPhone12Summary, iPhone14ProSummary]
    }
    
    private func getChipInfo() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        // Map identifiers to human-readable chip names
        switch identifier {
        case "iPhone13,3": return "A14 Bionic"
        case "iPhone15,2": return "A16 Bionic"
        case "iPhone14,7": return "A15 Bionic"
        case "iPhone12,1": return "A13 Bionic"
        default: return identifier
        }
    }
    
    private func simulateBenchmarkResults(for device: String) -> [ModelType: BenchmarkResult] {
        var results: [ModelType: BenchmarkResult] = [:]
        
        // Performance varies by device
        let performanceFactor: Double = device.contains("14 Pro") ? 1.0 : 1.8  // iPhone 14 Pro is faster
        
        for modelType in ModelType.allCases {
            let ttfa = TimeInterval.random(in: 0.030...0.080) / performanceFactor
            let avgLatency = TimeInterval.random(in: 0.035...0.090) / performanceFactor
            let p95Latency = TimeInterval.random(in: 0.060...0.120) / performanceFactor
            let maxLatency = TimeInterval.random(in: 0.080...0.200) / performanceFactor
            let fullProcessingTime = TimeInterval.random(in: 15...45) / performanceFactor
            let rtf = fullProcessingTime / 20.0  // Assuming 20-second audio
            let cpuUsage = Double.random(in: 25...65) * performanceFactor
            let ramUsage = Double.random(in: 120...250) * performanceFactor
            
            // Adjust output file path based on device and model
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = formatter.string(from: Date())
            let outputFileName = "\(modelType.displayName)_\(device)_\(timestamp).wav"
            let outputFilePath = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName).path
            
            results[modelType] = BenchmarkResult(
                modelType: modelType,
                ttfa: ttfa,
                avgLatency: avgLatency,
                p50Latency: avgLatency * 0.8,  // Approximation
                p95Latency: p95Latency,
                maxLatency: maxLatency,
                fullProcessingTime: fullProcessingTime,
                rtf: rtf,
                cpuUsage: cpuUsage,
                ramUsage: ramUsage,
                outputFilePath: outputFilePath
            )
        }
        
        return results
    }
    
    func exportComparisonReport() -> String {
        var csvContent = "Device Comparison Report\n\n"
        
        for summary in benchmarkSummaries {
            csvContent += "Device: \(summary.deviceInfo.name)\n"
            csvContent += "Model: \(summary.deviceInfo.model)\n"
            csvContent += "OS Version: \(summary.deviceInfo.osVersion)\n"
            csvContent += "Chip: \(summary.deviceInfo.chip)\n"
            csvContent += "Memory: \(summary.deviceInfo.memory)\n\n"
            
            csvContent += summary.formattedCSV
            csvContent += "\n\n"
        }
        
        return csvContent
    }
}