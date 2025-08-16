import SwiftUI

struct DirectoryNameView: View {
    let directory: BenchmarkDirectory
    @State private var isPressed = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(directory.name)
            
            Text(directory.url.path)
                .font(.subheadline)
                .foregroundStyle(Color.gray)
        }
    }
}
