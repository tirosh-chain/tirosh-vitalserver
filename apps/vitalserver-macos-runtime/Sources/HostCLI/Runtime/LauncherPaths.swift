import Bootstrap

typealias LauncherPaths = Bootstrap.LauncherPaths

extension LauncherPaths {
    static func resolve() -> LauncherPaths {
        Bootstrap.LauncherPaths.resolve(
            vmHomeEnvironmentKey: Constants.Environment.vmHome,
            defaultHomePathComponents: Constants.Paths.defaultHomePathComponents
        )
    }
}
