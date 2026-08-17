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

    // FIX: a result can be `available == true` and still have failed
    // mid-stream (BenchmarkManager sets available:true, status:"FAILED" when
    // processor.process() throws after the model loaded fine). The status
    // badge now reflects that -- green only for a clean, error-free success.
    private var isTrulySuccessful: Bool { result.available && result.errorMessage == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(result.modelType.displayName).font(.headline)
                Spacer()
                Text(result.status).foregroundColor(isTrulySuccessful ? .green : .orange)
            }
            if result.available {
                Text("TTFA: \(String(format: "%.2f ms", result.ttfa * 1000))")
                Text("Avg / P50 / P95 / Max: \(String(format: "%.2f / %.2f / %.2f / %.2f ms", result.avgLatency * 1000, result.p50Latency * 1000, result.p95Latency * 1000, result.maxLatency * 1000))")
                Text("Full: \(String(format: "%.3f s", result.fullProcessingTime)) • RTF: \(String(format: "%.3f", result.rtf))")
                Text("CPU: \(String(format: "%.1f%%", result.cpuUsage)) • RAM: \(String(format: "%.0f MB", result.ramUsage))")
                Text("Chunks: \(result.processedChunks)/\(result.totalChunks)"
                     + (result.droppedChunks > 0 ? " • native-уровня сбоев: \(result.droppedChunks)" : ""))
            }
            // FIX: previously this was `else if let error = result.errorMessage`,
            // so whenever `available == true` (model loaded fine but failed
            // partway through processing) the real error text was computed
            // by BenchmarkManager but never reached the screen. Now it's
            // shown any time it's present, regardless of `available`.
            if let error = result.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }.padding(.vertical, 6)
    }
}

