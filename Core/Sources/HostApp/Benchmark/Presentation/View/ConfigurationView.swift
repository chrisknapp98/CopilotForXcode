import SwiftUI

struct ConfigurationView: View {
    @State private var currentOutputDirectory: String = ""
    @State private var currentOpenAIKey: String = ""
    @StateObject var viewModel: ConfigurationViewModel
    @Environment(\.dismiss) private var dismiss

    private let labelWidth: CGFloat = 120
    
    init(module: BenchmarkModuleType) {
        self._viewModel = StateObject(wrappedValue: module.provide())
    }
    
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                Text("OpenAI API Key:")
                    .frame(width: labelWidth, alignment: .leading)
                TextField("Key", text: $currentOpenAIKey, prompt: Text("Key"))
                    .textFieldStyle(PlainTextFieldStyle())
            }
            .padding([.top, .horizontal])
            HStack(alignment: .top) {
                Text("Output Directory:")
                    .frame(width: labelWidth, alignment: .leading)
                VStack {
                    TextField("Output Directory", text: $currentOutputDirectory, prompt: Text("Directory"))
                        .textFieldStyle(PlainTextFieldStyle())
                    Button {
                        selectDirectory()
                    } label: {
                        Label("Select...", systemImage: "folder")
                    }
                    .padding()
                }
            }
            .padding()
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    viewModel.saveOutputDirectory(currentOutputDirectory)
                    viewModel.saveOpenAIKey(currentOpenAIKey)
                    dismiss()
                }
            }
            .padding([.horizontal, .bottom])
        }
        .onAppear {
            currentOutputDirectory = viewModel.outputDirectory
            currentOpenAIKey = viewModel.openAIKey
        }
    }
    
    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: currentOutputDirectory)

        if panel.runModal() == .OK {
            if let url = panel.url {
                currentOutputDirectory = url.path
            }
        }
    }
}
