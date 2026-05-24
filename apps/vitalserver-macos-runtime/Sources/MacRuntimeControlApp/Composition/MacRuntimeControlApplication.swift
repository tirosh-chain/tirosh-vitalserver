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
            Button(GeneratedRelease.vitalServerName) {
                viewModel.openVitalServer()
            }
            Button(GeneratedRelease.redisUIName) {
                viewModel.openRedisUI()
            }
            Button(GeneratedRelease.swaggerUIName) {
                viewModel.openSwagger()
            }
        }
    }
}
