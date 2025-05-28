import SwiftUI

struct DirectoryNameView: View {
    let directory: BenchmarkDirectory
    @State private var isPressed = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Text(isPressed ? directory.url.path : directory.name)
            .foregroundStyle(isPressed ? Color.gray : colorScheme == .dark ? Color.white : Color.black)
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
