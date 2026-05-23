import SwiftUI

@main
struct MacRuntimeControlApplication: App {
    @StateObject private var environment = MacRuntimeControlEnvironment.live()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment.viewModel)
                .frame(minWidth: 560, minHeight: 420)
        }
        .windowStyle(.titleBar)
        .commands {
            MacRuntimeControlCommands(viewModel: environment.viewModel)
        }
    }
}

private struct MacRuntimeControlCommands: Commands {
    @ObservedObject var viewModel: RuntimeViewModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            Button(AppConstants.Actions.openVitalFilesDirectory) {
                viewModel.openVitalFilesDirectory()
            }
            Menu(AppConstants.Labels.menuVitalFiles) {
                let folders = viewModel.vitalFileFolders()
                if folders.isEmpty {
                    Text(AppConstants.Labels.noVitalFileFolders)
                } else {
                    ForEach(folders) { folder in
                        Button(folder.name) {
                            viewModel.openFolder(folder.path)
                        }
                    }
                }
            }
        }
        CommandGroup(after: .toolbar) {
            Divider()
            Button(AppConstants.Actions.openVitalServer) {
                viewModel.openVitalServer()
            }
            Button(AppConstants.Actions.openRedisUI) {
                viewModel.openRedisUI()
            }
            Button(AppConstants.Actions.openSwagger) {
                viewModel.openSwagger()
            }
        }
    }
}
