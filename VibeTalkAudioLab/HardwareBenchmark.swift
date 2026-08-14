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
        let header = "Device,Model,TTFA,Avg,P50,P95,Max,Full,RTF,CPU,RAM,Status\n"
        let rows = results.values.sorted { $0.modelType.displayName < $1.modelType.displayName }.map {
            "\(deviceInfo.name),\($0.modelType.displayName),\(String(format: "%.4f", $0.ttfa)),\(String(format: "%.4f", $0.avgLatency)),\(String(format: "%.4f", $0.p50Latency)),\(String(format: "%.4f", $0.p95Latency)),\(String(format: "%.4f", $0.maxLatency)),\(String(format: "%.4f", $0.fullProcessingTime)),\(String(format: "%.3f", $0.rtf)),\(String(format: "%.1f", $0.cpuUsage)),\(String(format: "%.1f", $0.ramUsage)),\($0.status)"
        }
        return header + rows.joined(separator: "\n")
    }
}

final class HardwareBenchmarkManager: ObservableObject {
    @Published var benchmarkSummaries: [BenchmarkSummary] = []
    @Published var message: String = ""

    /// A single iPhone cannot produce a real iPhone 12 vs 14 Pro comparison.
    /// This manager therefore records only measurements actually made on the current device.
    func recordCurrentDevice(results: [ModelType: BenchmarkResult]) {
        let info = DeviceInfo(name: UIDevice.current.name, model: UIDevice.current.model,
                              osVersion: UIDevice.current.systemVersion, chip: getChipInfo(),
                              memory: "\(ProcessInfo.processInfo.physicalMemory / 1024 / 1024) MB")
        benchmarkSummaries = [BenchmarkSummary(deviceInfo: info, results: results)]
        message = "Результаты относятся только к этому физическому устройству. Для iPhone 12 и 14 Pro нужны отдельные прогоны."
    }

    func runHardwareComparisonBenchmark() {
        benchmarkSummaries.removeAll()
        message = "Сначала запусти реальный Benchmark на этом iPhone; симулированные результаты отключены."
    }

    private func getChipInfo() -> String {
        var systemInfo = utsname(); uname(&systemInfo)
        let identifier = Mirror(reflecting: systemInfo.machine).children.reduce("") { r, e in
            guard let v = e.value as? Int8, v != 0 else { return r }
            return r + String(UnicodeScalar(UInt8(v)))
        }
        switch identifier {
        case "iPhone13,3": return "A14 Bionic"
        case "iPhone15,2": return "A16 Bionic"
        case "iPhone14,7": return "A15 Bionic"
        case "iPhone12,1": return "A13 Bionic"
        case "iPhone13,2": return "A14 Bionic"
        case "iPhone13,4": return "A14 Bionic"
        default: return identifier
        }
    }

    func exportComparisonReport() -> String {
        benchmarkSummaries.map { s in
            "Device: \(s.deviceInfo.name)\nModel identifier: \(s.deviceInfo.model)\nOS: \(s.deviceInfo.osVersion)\nChip: \(s.deviceInfo.chip)\nMemory: \(s.deviceInfo.memory)\n\n\(s.formattedCSV)"
        }.joined(separator: "\n\n")
    }
}
