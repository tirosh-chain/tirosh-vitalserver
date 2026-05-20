import SwiftUI

@main
struct TiroshVitalServerInstallerApp: App {
    var body: some Scene {
        WindowGroup {
            InstallerView()
        }
        .windowResizability(.contentSize)
    }
}
