import SwiftUI

@main
struct ManagerApplication: App {
    @StateObject private var controller = RuntimeController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .frame(minWidth: 560, minHeight: 420)
        }
        .windowStyle(.titleBar)
        .commands {
            ManagerCommands(controller: controller)
        }
    }
}

private struct ManagerCommands: Commands {
    @ObservedObject var controller: RuntimeController

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            Button(AppConstants.Actions.openVitalFilesDirectory) {
                controller.openVitalFilesDirectory()
            }
            Menu(AppConstants.Labels.menuVitalFiles) {
                let folders = controller.vitalFileFolders()
                if folders.isEmpty {
                    Text(AppConstants.Labels.noVitalFileFolders)
                } else {
                    ForEach(folders) { folder in
                        Button(folder.name) {
                            controller.openFolder(folder.path)
                        }
                    }
                }
            }
        }
        CommandGroup(after: .toolbar) {
            Divider()
            Button(AppConstants.Actions.openVitalServer) {
                controller.openVitalServer()
            }
            Button(AppConstants.Actions.openRedisUI) {
                controller.openRedisUI()
            }
            Button(AppConstants.Actions.openSwagger) {
                controller.openSwagger()
            }
        }
    }
}
