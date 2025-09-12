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
                    
                    HStack(spacing: 20) {
                        Spacer()
                        Picker("Context Level Limit: ", selection: $viewModel.contextLevelLimit) {
                            ForEach(ContextLevelLimit.allCases, id: \.self) { limit in
                                Text(limit.name).tag(limit)
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        
                        Text("Context File Amount Limit:")
                        let numberFormatter: NumberFormatter = {
                            let f = NumberFormatter()
                            f.numberStyle = .none
                            return f
                        }()
                        TextField("Optional", value: $viewModel.contextFileAmountLimit, formatter: numberFormatter)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 100)
                    }
                    .padding(.bottom)
                    
                    ForEach(viewModel.benchmarkDirectories, id: \.self) { directory in
                        BenchmarkDirectoryEntryView(
                            directory: directory,
                            module: module
                        )
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
}
