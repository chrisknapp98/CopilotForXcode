import SwiftUI

struct AddDirectoryButtonView: View {
    private let module: BenchmarkModuleType
    @State private var isShowingSheet = false
    
    init(module: BenchmarkModuleType) {
        self.module = module
    }
    
    var body: some View {
        Button {
            isShowingSheet.toggle()
        } label : {
            Label("add directory", systemImage: "plus")
                .foregroundStyle(.foreground) // to remove green accent color from system image
        }
        .sheet(isPresented: $isShowingSheet) {
            AddDirectoryView(module: module)
        }
    }
}
