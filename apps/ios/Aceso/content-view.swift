import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack(alignment: .top) {
            AppShellView()
            SyncToastHost()
        }
        .acesoScreenBackground()
    }
}

#Preview {
    ContentView()
        .environment(WhoopBLEClient(family: .whoop4))
}
