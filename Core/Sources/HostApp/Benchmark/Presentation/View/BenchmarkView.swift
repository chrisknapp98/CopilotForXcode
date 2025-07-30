import SwiftUI

struct BenchmarkView: View {
    private let module: BenchmarkModuleType
    @StateObject private var viewModel: BenchmarkViewModel
    
    private let taskStatusInfoHeight: CGFloat = 150.0
    
    init(module: BenchmarkModuleType) {
        self.module = module
        _viewModel = StateObject(wrappedValue: module.provide())
    }
    
    var body: some View {
        VStack {
            ScrollView {
                VStack {
                    HStack(spacing: 20) {
                        Text("Run Benchmark")
                            .font(.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("Multi File Context Enabled", isOn: $viewModel.isMultiFileContextEnabled)
                        OutputConfigurationButtonView(module: module)
                    }
                    .padding(.vertical)
                    VStack {
                        ForEach(viewModel.benchmarkDirectories, id: \.self) { directory in
                            HStack {
                                DirectoryNameView(directory: directory)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    Task {
                                        try? await viewModel.runBenchmark(for: directory)
                                    }
                                } label: {
                                    Image(systemName: "play")
                                }
                                Button {
                                    NSWorkspace.shared.open(directory.url)
                                } label: {
                                    Image(systemName: "folder")
                                }
                                Button {
                                    viewModel.deleteDirectory(directory)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    AddDirectoryButtonView(module: module)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
            }
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.taskStates.isEmpty {
                    Text("💤 No benchmarks running right now.")
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("📋 Task Status")
                            .font(.headline)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(viewModel.taskStates.enumerated()), id: \.offset) { index, taskStatus in
                                    HStack {
                                        Text("Task \(index + 1)")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        Group {
                                            switch taskStatus {
                                            case .notStarted:
                                                Text("🕒")
                                                    .accessibilityLabel("Not started")
                                            case .running:
                                                ProgressView()
                                                    .scaleEffect(0.6)
                                                    .accessibilityLabel("Running")
                                            case .success:
                                                Text("✅")
                                                    .accessibilityLabel("Success")
                                            case .failure:
                                                Text("❌")
                                                    .accessibilityLabel("Failed")
                                            }
                                        }
                                        .frame(width: 24, height: 24, alignment: .center)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .frame(height: taskStatusInfoHeight)
                }
            }
            .frame(maxWidth: .infinity, minHeight: taskStatusInfoHeight, alignment: .leading)
            .padding()
            .background(Color(.windowBackgroundColor))
            .cornerRadius(8)
        }
        .onAppear {
            viewModel.loadBenchmarkDirectories()
        }
    }
}
