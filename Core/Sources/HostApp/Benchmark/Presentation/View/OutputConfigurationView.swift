import SwiftUI

struct OutputConfigurationView: View {
    @State private var currentOutputDirectory: String = ""
    @StateObject var viewModel: OutputConfigurationViewModel
    @Environment(\.dismiss) private var dismiss

    private let labelWidth: CGFloat = 120
    
    init(module: BenchmarkModuleType) {
        self._viewModel = StateObject(wrappedValue: module.provide())
    }
    
    var body: some View {
        VStack {
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
                    dismiss()
                }
            }
            .padding([.horizontal, .bottom])
        }
        .onAppear {
            currentOutputDirectory = viewModel.outputDirectory
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
