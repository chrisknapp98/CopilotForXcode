import SwiftUI

struct DirectoryNameView: View {
    let directory: BenchmarkDirectory
    @State private var isPressed = false

    var body: some View {
        Text(isPressed ? directory.url.path : directory.name)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged({ _ in
                        withAnimation {
                            isPressed = true
                        }
                    })
                    .onEnded({ _ in
                        withAnimation {
                            isPressed = false
                        }
                    })
            )
            .animation(.easeInOut(duration: 0.2), value: isPressed)
    }
}
