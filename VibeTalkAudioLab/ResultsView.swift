import SwiftUI

struct ResultsView: View {
    @ObservedObject var benchmarkManager: BenchmarkManager
    
    var body: some View {
        VStack {
            Text("Benchmark Results")
                .font(.title)
                .fontWeight(.bold)
                .padding()
            
            if benchmarkManager.isRunning {
                ProgressView("Running benchmark...")
                    .padding()
            } else if !benchmarkManager.results.isEmpty {
                List {
                    ForEach(ModelType.allCases, id: \.self) { modelType in
                        if let result = benchmarkManager.results[modelType] {
                            ResultRowView(result: result)
                        }
                    }
                }
            } else {
                Text("No benchmark results yet. Run a benchmark to see results.")
                    .foregroundColor(.secondary)
                    .padding()
            }
            
            // Export button
            if !benchmarkManager.results.isEmpty {
                Button("Export Results") {
                    exportResults()
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
    }
    
    private func exportResults() {
        // Create CSV content
        var csvContent = "Device,Model,Chunk,TTFA,Avg,P95,Full,RTF,CPU,RAM\n"
        
        // For demo purposes, we'll use placeholder device info
        let deviceInfo = UIDevice.current.name
        
        for modelType in ModelType.allCases {
            if let result = benchmarkManager.results[modelType] {
                csvContent += "\(deviceInfo),\(result.modelType.displayName),\(benchmarkManager.results.count > 0 ? "20ms" : ""),\(String(format: "%.3f", result.ttfa)),\(String(format: "%.3f", result.avgLatency)),\(String(format: "%.3f", result.p95Latency)),\(String(format: "%.3f", result.fullProcessingTime)),\(String(format: "%.2f", result.rtf)),\(String(format: "%.1f", result.cpuUsage)),\(String(format: "%.1f", result.ramUsage))\n"
            }
        }
        
        // Save to documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filePath = documentsPath.appendingPathComponent("benchmark_results.csv")
        
        do {
            try csvContent.write(to: filePath, atomically: true, encoding: .utf8)
            print("Results exported to: \(filePath.path)")
        } catch {
            print("Error exporting results: \(error)")
        }
    }
}

struct ResultRowView: View {
    let result: BenchmarkResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.modelType.displayName)
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TTFA: \(String(format: "%.0f ms", result.ttfa * 1000))")
                    Text("Avg: \(String(format: "%.0f ms", result.avgLatency * 1000))")
                    Text("P95: \(String(format: "%.0f ms", result.p95Latency * 1000))")
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("RTF: \(String(format: "%.2f", result.rtf))")
                    Text("CPU: \(String(format: "%.1f%%", result.cpuUsage))")
                    Text("RAM: \(String(format: "%.0f MB", result.ramUsage))")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
struct ResultsView_Previews: PreviewProvider {
    static var previews: some View {
        ResultsView(benchmarkManager: BenchmarkManager())
    }
}
#endif