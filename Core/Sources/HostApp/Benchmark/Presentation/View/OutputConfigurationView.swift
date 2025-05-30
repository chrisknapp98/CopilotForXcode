import SwiftUI

struct OutputConfigurationView: View {
    @State private var currentOutputDirectory: String = ""
    @StateObject var viewModel: OutputConfigurationViewModel
    @Environment(\.dismiss) private var dismiss

    private let labelWidth: CGFloat = 100
    
    init(module: BenchmarkModuleType) {
        self._viewModel = StateObject(wrappedValue: module.provide())
    }
    
    var body: some View {
        HStack {
            Text("Output Directory:")
                .frame(width: labelWidth, alignment: .leading)
            TextField("Output Directory", text: $currentOutputDirectory, prompt: Text("Directory"))
                .textFieldStyle(PlainTextFieldStyle())
                
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
        .onAppear {
            currentOutputDirectory = viewModel.outputDirectory
        }
    }
}
