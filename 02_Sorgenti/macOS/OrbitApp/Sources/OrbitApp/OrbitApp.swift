import SwiftUI

@main
struct OrbitApp: App {
    var body: some Scene {
        WindowGroup("Orbit") {
            ContentView(client: OrbitClient())
                .frame(minWidth: 620, minHeight: 500)
        }
        .windowToolbarStyle(.unified)
    }
}
