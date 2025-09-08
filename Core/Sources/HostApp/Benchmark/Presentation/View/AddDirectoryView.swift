import SwiftUI

struct AddDirectoryView: View {
    @State private var currentDirectoryName: String = ""
    @State private var currentDirectory: String = ""
    @StateObject var viewModel: AddDirectoryViewModel
    @Environment(\.dismiss) private var dismiss
    
    private let labelWidth: CGFloat = 100
    
    init(module: BenchmarkModuleType) {
        _viewModel = StateObject(wrappedValue: module.provide())
    }
    
    var body: some View {
        VStack {
            HStack {
                Text("Name")
                    .frame(width: labelWidth, alignment: .leading)
                TextField("Name", text: $currentDirectoryName, prompt: Text("Project X"))
                    .textFieldStyle(PlainTextFieldStyle())
            }
            HStack {
                Text("Directory")
                    .frame(width: labelWidth, alignment: .leading)
                TextField("Directory", text: $currentDirectory, prompt: Text("/path/to/directory"))
                    .textFieldStyle(PlainTextFieldStyle())
            }
            
        }
        .padding()
        
        HStack {
            Button("Cancel") {
                dismiss()
            }
            Button("Save") {
                viewModel.saveNewDirectory(name: currentDirectoryName, directory: currentDirectory)
                dismiss()
            }
        }
        .padding([.horizontal, .bottom])
    }
}
