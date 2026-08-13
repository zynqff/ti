# VibeTalk Audio Lab - Build Instructions

## Prerequisites

- Xcode 15 or later
- iOS 15.0 or later
- macOS 12.0 or later

## Project Structure

```
VibeTalkAudioLab/
├── VibeTalkAudioLab/                 # Main iOS app source code
│   ├── App.swift                    # App entry point
│   ├── ContentView.swift            # Main content view
│   ├── MainBenchmarkView.swift      # Main benchmark UI
│   ├── AudioManager.swift           # Audio recording/playback management
│   ├── AudioProcessor.swift         # Audio processing interfaces
│   ├── BenchmarkManager.swift       # Benchmark orchestration
│   ├── ResultsView.swift            # Results display
│   ├── BlindTestView.swift          # A/B testing interface
│   ├── ContinuousStreamTest.swift   # Long-running test
│   ├── StreamingAudioProcessor.swift # Real-time processing pipeline
│   ├── RealTimeBenchmark.swift      # Live benchmarking
│   ├── HardwareBenchmark.swift      # Cross-device comparison
│   ├── AudioUtils.swift             # Audio utility functions
│   └── Info.plist                   # App configuration
└── VibeTalkAudioLab.xcodeproj/      # Xcode project
```

## Building the Application

1. Open the project in Xcode:
   ```
   open VibeTalkAudioLab.xcodeproj
   ```

2. Select your target device (iPhone 12 or iPhone 14 Pro simulator, or physical device)

3. Build and run the application:
   - Press Cmd+R or click the Run button in Xcode

## Integration Notes

### Audio Processing Models

The current implementation includes placeholder implementations for:

- RNNoise
- DeepFilterNet2 Lite
- DeepFilterNet3

To integrate the actual models:

1. Add the C/C++ libraries to the project
2. Create Objective-C++ wrappers for the C libraries
3. Update the AudioProcessor implementations to call the actual models

### Required Permissions

The app requires microphone access. The Info.plist already includes the required permission:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to the microphone to record audio for denoise benchmarking.</string>
```

## Testing Scenarios

The application supports testing in the following scenarios:

1. **Quiet Room** - Normal speech in quiet environment
2. **Fan Noise** - Speech with nearby fan noise
3. **Street Noise** - Urban ambient noise
4. **Café** - Multiple voices and background noise
5. **Whisper** - Very quiet speech

## Benchmark Metrics

The application measures:

- **TTFA** (Time To First Audio) - Critical metric for real-time processing
- **Average Latency** - Average processing delay
- **P50/P95 Latency** - Percentile-based latency metrics
- **Max Latency** - Maximum observed processing delay
- **Full Processing Time** - Total time to process entire recording
- **RTF** (Real-Time Factor) - Processing speed relative to real-time
- **CPU Usage** - Processor utilization during processing
- **RAM Usage** - Memory consumption during processing

## Hardware Testing

The application is designed to run on both iPhone 12 and iPhone 14 Pro for comparative benchmarking.

## Continuous Streaming Test

Includes a 20-minute continuous streaming test to evaluate stability and memory usage over extended periods.

## Exporting Results

Benchmark results can be exported as CSV files for further analysis.