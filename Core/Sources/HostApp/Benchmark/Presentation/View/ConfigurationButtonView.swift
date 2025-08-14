import SwiftUI

struct ConfigurationButtonView: View {
    private let module: BenchmarkModuleType
    @State private var isShowingSheet = false
    
    init(module: BenchmarkModuleType) {
        self.module = module
    }
    
    var body: some View {
        Button {
            isShowingSheet.toggle()
        } label : {
            Label("Configure", systemImage: "gear")
        }
        .sheet(isPresented: $isShowingSheet) {
            ConfigurationView(module: module)
        }
    }
}

