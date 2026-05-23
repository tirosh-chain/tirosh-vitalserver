import Foundation
import HostInfrastructure

struct LauncherPaths {
    let home: URL
    let installed: InstalledRuntimePaths
    let config: URL
    let pidFile: URL

    // Keep all mutable runtime state outside the repository by default.
    static func resolve() -> LauncherPaths {
        let environment = ProcessInfo.processInfo.environment
        let homePath = environment[Constants.Environment.vmHome]
            ?? Constants.Paths.defaultHomePathComponents.reduce(
                FileManager.default.homeDirectoryForCurrentUser
            ) { url, component in
                url.appendingPathComponent(component)
            }.path
        let home = URL(fileURLWithPath: homePath)
        let installed = InstalledRuntimePaths(runtimeHome: home)
        return LauncherPaths(
            home: home,
            installed: installed,
            config: installed.vmConfig,
            pidFile: installed.pidFile
        )
    }

    var cleanableRuntimePaths: [URL] {
        [
            installed.runtimeDirectory,
            installed.centralRuntimeLogsDirectory,
            installed.logsDirectory,
            installed.hostRunDirectory,
        ]
    }
}
