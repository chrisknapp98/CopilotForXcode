import SwiftUI

struct BenchmarkView: View {
    private let module: BenchmarkModuleType
    @StateObject private var viewModel: BenchmarkViewModel
    
    init(module: BenchmarkModuleType) {
        self.module = module
        _viewModel = StateObject(wrappedValue: module.provide())
    }
    
    var body: some View {
        ScrollView {
            VStack {
                HStack {
                    Text("Run Benchmark")
                        .font(.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    OutputConfigurationButtonView(module: module)
                }
                .padding(.vertical)
                VStack {
                    ForEach(viewModel.benchmarkDirectories, id: \.self) { directory in
                        HStack {
                            DirectoryNameView(directory: directory)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                viewModel.runBenchmark(for: directory)
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
        .onAppear {
            viewModel.loadBenchmarkDirectories()
        }
    }
}
