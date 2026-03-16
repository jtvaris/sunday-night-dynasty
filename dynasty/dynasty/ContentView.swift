import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        NavigationStack {
            MainMenuView()
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Career.self, inMemory: true)
}
