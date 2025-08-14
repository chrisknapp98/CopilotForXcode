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
                        Picker("Language Model: ", selection: $viewModel.selectedLanguageModel) {
                            ForEach(GenAILanguageModel.allCases, id: \.self) { model in
                                Text(model.name).tag(model)
                            }
                        }
                        ConfigurationButtonView(module: module)
                    }
                    .padding(.vertical)
                    ForEach(viewModel.benchmarkDirectories, id: \.self) { directory in
                        VStack {
                            VStack(alignment: .leading, spacing: 10) {
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
                        taskList(directory: directory)
                    }
                    AddDirectoryButtonView(module: module)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
            }
        }
        .onAppear {
            viewModel.loadBenchmarkDirectories()
        }
    }
    
    func taskList(directory: BenchmarkDirectory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
//            Text("📋 Task Status")
//                .font(.headline)
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(viewModel.taskStates.enumerated()), id: \.offset) { index, taskStatus in
                    HStack {
                        Button {
                            Task {
                                await viewModel.runTask(index: index, in: directory)
                            }
                        } label: {
                            Image(systemName: "play")
                        }
                        
                        Text("Task \(index + 1)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Group {
                            switch taskStatus {
                            case .notStarted:
                                Text("")
                                    .accessibilityLabel("Not started")
                            case .scheduled:
                                Text("🕒")
                                    .accessibilityLabel("Scheduled")
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
        .padding(.leading, 20)
    }
}
