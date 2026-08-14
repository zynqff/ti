import SwiftUI
import UIKit

struct ResultsView: View {
    @ObservedObject var benchmarkManager: BenchmarkManager

    var body: some View {
        VStack {
            Text("Benchmark Results").font(.title).bold().padding()
            if benchmarkManager.isRunning { ProgressView("Running real benchmark…").padding() }
            else if let error = benchmarkManager.lastError { Text(error).foregroundColor(.red).padding() }
            else if !benchmarkManager.results.isEmpty {
                List(ModelType.allCases, id: \.self) { type in
                    if let result = benchmarkManager.results[type] { ResultRowView(result: result) }
                }
            } else { Text("No results yet.").foregroundColor(.secondary) }
        }
    }
}

struct ResultRowView: View {
    let result: BenchmarkResult
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(result.modelType.displayName).font(.headline)
                Spacer()
                Text(result.status).foregroundColor(result.available ? .green : .orange)
            }
            if result.available {
                Text("TTFA: \(String(format: "%.2f ms", result.ttfa * 1000))")
                Text("Avg / P50 / P95 / Max: \(String(format: "%.2f / %.2f / %.2f / %.2f ms", result.avgLatency * 1000, result.p50Latency * 1000, result.p95Latency * 1000, result.maxLatency * 1000))")
                Text("Full: \(String(format: "%.3f s", result.fullProcessingTime)) • RTF: \(String(format: "%.3f", result.rtf))")
                Text("CPU: \(String(format: "%.1f%%", result.cpuUsage)) • RAM: \(String(format: "%.0f MB", result.ramUsage))")
                Text("Chunks: \(result.processedChunks)/\(result.totalChunks)")
            } else if let error = result.errorMessage { Text(error).foregroundColor(.orange) }
        }.padding(.vertical, 6)
    }
}
