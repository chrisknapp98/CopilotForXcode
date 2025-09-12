import SwiftUI

struct BenchmarkDirectoryEntryView: View {
    @StateObject private var viewModel: BenchmarkDirectoryEntryViewModel
    @State private var isShowingTaskList = false
    
    init(directory: BenchmarkDirectory, module: BenchmarkModuleType) {
        _viewModel = StateObject(wrappedValue: module.provide(directory: directory))
    }
    
    
    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    DirectoryNameView(directory: viewModel.directory)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        Task {
                            try? await viewModel.runBenchmark(for: viewModel.directory)
                        }
                    } label: {
                        Label("Run all Tasks", systemImage: "play")
                    }
                    Button {
                        NSWorkspace.shared.open(viewModel.directory.url)
                    } label: {
                        Image(systemName: "folder")
                    }
                    Button {
                        viewModel.deleteDirectory(viewModel.directory)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    Button {
                        withAnimation {
                            isShowingTaskList.toggle()
                        }
                    } label: {
                        Image(systemName: isShowingTaskList ? "chevron.up.circle" : "chevron.down.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isShowingTaskList ? "Hide tasks" : "Show tasks")
                    .accessibilityHint("Tap to toggle task list visibility")
                    .padding(.horizontal, 10)
                }
            }
            if isShowingTaskList {
                taskList(directory: viewModel.directory)
            }
        }
    }
    
    func taskList(directory: BenchmarkDirectory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(viewModel.taskStates.enumerated()), id: \.offset) { index, taskStatus in
                    HStack(spacing: 20) {
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
