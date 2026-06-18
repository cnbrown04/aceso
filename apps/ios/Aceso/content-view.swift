import SwiftUI
import WhoopSDK

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
        .environment(WhoopSDK.makeBLEClient(family: .whoop4))
}
