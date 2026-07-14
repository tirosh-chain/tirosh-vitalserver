import Foundation
import Errors

public struct RuntimeInstallPermissionInput: Equatable, Sendable {
    public let proxyPort: Int

    public init(proxyPort: Int) {
        self.proxyPort = proxyPort
    }
}

public struct RuntimeInstallPermissionContext {
    public let runtimeHome: URL
    public let nginxDirectory: URL
    public let runtimeStateDatabase: URL
    public let proxyLaunchDaemonPlist: String
    public let serviceLaunchDaemonPlists: [String]
    public let chownExecutable: String
    public let chmodExecutable: String
    public let plistBuddyExecutable: String

    public init(
        runtimeHome: URL,
        nginxDirectory: URL,
        runtimeStateDatabase: URL,
        proxyLaunchDaemonPlist: String,
        serviceLaunchDaemonPlists: [String],
        chownExecutable: String,
        chmodExecutable: String,
        plistBuddyExecutable: String
    ) {
        self.runtimeHome = runtimeHome
        self.nginxDirectory = nginxDirectory
        self.runtimeStateDatabase = runtimeStateDatabase
        self.proxyLaunchDaemonPlist = proxyLaunchDaemonPlist
        self.serviceLaunchDaemonPlists = serviceLaunchDaemonPlists
        self.chownExecutable = chownExecutable
        self.chmodExecutable = chmodExecutable
        self.plistBuddyExecutable = plistBuddyExecutable
    }
}

public struct RuntimeInstallPermissionOperations {
    public let runRequired: (String, [String]) throws -> Void

    public init(runRequired: @escaping (String, [String]) throws -> Void) {
        self.runRequired = runRequired
    }
}

public struct RuntimeInstallPermissionConfigurator {
    public let context: RuntimeInstallPermissionContext
    public let operations: RuntimeInstallPermissionOperations

    public init(
        context: RuntimeInstallPermissionContext,
        operations: RuntimeInstallPermissionOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func configure(input: RuntimeInstallPermissionInput) throws {
        try operations.runRequired(context.chownExecutable, ["-R", "root:wheel", context.runtimeHome.path])
        try operations.runRequired(context.chownExecutable, ["-R", "root:wheel", context.nginxDirectory.path])
        try operations.runRequired(context.chmodExecutable, ["0600", context.runtimeStateDatabase.path])
        try operations.runRequired(
            context.plistBuddyExecutable,
            [
                "-c",
                "Set :EnvironmentVariables:VITALSERVER_PROXY_PORT \(input.proxyPort)",
                context.proxyLaunchDaemonPlist,
            ]
        )
        for plist in context.serviceLaunchDaemonPlists {
            try operations.runRequired(context.chmodExecutable, ["0644", plist])
            try operations.runRequired(context.chownExecutable, ["root:wheel", plist])
        }
    }
}
