import Foundation
import OutboundAdapters
import Errors

public struct LauncherPaths {
    public let home: URL
    public let installed: InstalledRuntimePaths
    public let config: URL
    public let pidFile: URL

    public init(
        home: URL,
        installed: InstalledRuntimePaths,
        config: URL,
        pidFile: URL
    ) {
        self.home = home
        self.installed = installed
        self.config = config
        self.pidFile = pidFile
    }

    public static func resolve(
        environment: [String: String],
        homeDirectory: URL,
        vmHomeEnvironmentKey: String,
        defaultHomePathComponents: [String]
    ) -> LauncherPaths {
        let homePath = environment[vmHomeEnvironmentKey]
            ?? defaultHomePathComponents.reduce(homeDirectory) { url, component in
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

    public var cleanableRuntimePaths: [URL] {
        [
            installed.runtimeDirectory,
            installed.centralRuntimeLogsDirectory,
            installed.logsDirectory,
            installed.hostRunDirectory,
        ]
    }
}
