import Foundation

struct LauncherPaths {
    let home: URL
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
        return LauncherPaths(
            home: home,
            config: home.appendingPathComponent(Constants.Paths.configFile),
            pidFile: home
                .appendingPathComponent(Constants.Paths.runDirectory)
                .appendingPathComponent(Constants.Paths.pidFile)
        )
    }

    var cleanableRuntimePaths: [URL] {
        [
            home.appendingPathComponent(Constants.Paths.runtimeDirectory),
            home.appendingPathComponent(Constants.Paths.logsDirectory),
            home.appendingPathComponent(Constants.Paths.runDirectory),
        ]
    }
}
