import SwiftUI

struct OutputConfigurationButtonView: View {
    private let module: BenchmarkModuleType
    @State private var isShowingSheet = false
    
    init(module: BenchmarkModuleType) {
        self.module = module
    }
    
    var body: some View {
        Button {
            isShowingSheet.toggle()
        } label : {
            Label("Configure Output", systemImage: "gear")
        }
        .sheet(isPresented: $isShowingSheet) {
            OutputConfigurationView(module: module)
        }
    }
}

