import Application
import Contracts
import Foundation
import OutboundAdapters
import RuntimeControl
import Errors

struct RuntimeRedisRelayConfigurationWriter {
    let installedPaths: InstalledRuntimePaths
    let fileStore: RuntimeFileStore

    func ensureInstallConfiguration() throws {
        try createRelayDirectories()
        let document = try loadRuntimeControlSettings()
        try writeRuntimeControlSettingsIfMissing(document)

        switch fileStore.pathState(at: installedPaths.redisRelayConfig) {
        case .file:
            return
        case .missing:
            try writeRedisRelayTOML(settings: document.redisRelay)
        case .inspectFailed(let reason):
            throw LauncherError.runtimeOperationFailed(
                "Redis relay config path inspection failed path=\(installedPaths.redisRelayConfig.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw LauncherError.runtimeOperationFailed(
                "Redis relay config path state is unexpected path=\(installedPaths.redisRelayConfig.path) state=\(fileStore.pathState(at: installedPaths.redisRelayConfig).rawValue)"
            )
        }
    }

    func writeConfigured(_ settings: ConfigureRuntimeRedisRelaySettings) throws {
        try createRelayDirectories()
        let passwordConfigured = try writeRedisRelayTargetPassword(settings.target)
        let runtimeSettings = runtimeRedisRelaySettings(settings, passwordConfigured: passwordConfigured)
        try updateRuntimeControlSettings { document in
            document = RuntimeControlSettingsDocument(
                logArchiveRetentionDays: document.logArchiveRetentionDays,
                logArchiveMaximumGiB: document.logArchiveMaximumGiB,
                redisRelay: runtimeSettings
            )
        }
        try writeRedisRelayTOML(settings: runtimeSettings)
    }

    private func createRelayDirectories() throws {
        try fileStore.createDirectory(
            at: installedPaths.redisRelayConfigDirectory,
            withIntermediateDirectories: true
        )
        try fileStore.createDirectory(
            at: installedPaths.redisRelaySecretsDirectory,
            withIntermediateDirectories: true
        )
        try fileStore.createDirectory(
            at: installedPaths.redisRelayStatusDirectory,
            withIntermediateDirectories: true
        )
    }

    private func writeRuntimeControlSettingsIfMissing(
        _ document: RuntimeControlSettingsDocument
    ) throws {
        switch fileStore.pathState(at: installedPaths.runtimeControlSettings) {
        case .file:
            return
        case .missing:
            try writeRuntimeControlSettings(document)
        case .inspectFailed(let reason):
            throw LauncherError.runtimeOperationFailed(
                "runtime control settings path inspection failed path=\(installedPaths.runtimeControlSettings.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw LauncherError.runtimeOperationFailed(
                "runtime control settings path state is unexpected path=\(installedPaths.runtimeControlSettings.path) state=\(fileStore.pathState(at: installedPaths.runtimeControlSettings).rawValue)"
            )
        }
    }

    private func updateRuntimeControlSettings(
        _ update: (inout RuntimeControlSettingsDocument) throws -> Void
    ) throws {
        var settings = try loadRuntimeControlSettings()
        try update(&settings)
        try writeRuntimeControlSettings(settings)
    }

    private func writeRuntimeControlSettings(
        _ settings: RuntimeControlSettingsDocument
    ) throws {
        let data = try VMRuntimeConfigComposition.prettyJSONEncoder().encode(settings)
        try fileStore.createDirectory(
            at: installedPaths.runtimeControlSettings.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileStore.writeData(data, to: installedPaths.runtimeControlSettings, options: .atomic)
    }

    private func loadRuntimeControlSettings() throws -> RuntimeControlSettingsDocument {
        let url = installedPaths.runtimeControlSettings
        switch fileStore.pathState(at: url) {
        case .file:
            break
        case .missing:
            return RuntimeControlSettingsDocument()
        case .inspectFailed(let reason):
            throw LauncherError.runtimeOperationFailed(
                "runtime control settings path inspection failed path=\(url.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw LauncherError.runtimeOperationFailed(
                "runtime control settings path state is unexpected path=\(url.path) state=\(fileStore.pathState(at: url).rawValue)"
            )
        }
        let data = try fileStore.readData(url)
        return try JSONDecoder().decode(RuntimeControlSettingsDocument.self, from: data)
    }

    private func writeRedisRelayTargetPassword(
        _ target: ConfigureRuntimeRedisRelayTarget
    ) throws -> Bool {
        if target.clearPassword {
            try removeRedisRelayPasswordIfPresent()
            return false
        }
        if !target.password.isEmpty {
            try fileStore.writeData(
                Data(target.password.utf8),
                to: installedPaths.redisRelayTargetPassword,
                options: .atomic,
                posixPermissions: 0o600
            )
            return true
        }
        switch fileStore.pathState(at: installedPaths.redisRelayTargetPassword) {
        case .file:
            return target.passwordConfigured
        case .missing:
            return false
        case .inspectFailed(let reason):
            throw LauncherError.runtimeOperationFailed(
                "Redis relay password path inspection failed path=\(installedPaths.redisRelayTargetPassword.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw LauncherError.runtimeOperationFailed(
                "Redis relay password path state is unexpected path=\(installedPaths.redisRelayTargetPassword.path) state=\(fileStore.pathState(at: installedPaths.redisRelayTargetPassword).rawValue)"
            )
        }
    }

    private func removeRedisRelayPasswordIfPresent() throws {
        switch fileStore.pathState(at: installedPaths.redisRelayTargetPassword) {
        case .file:
            try fileStore.removeItem(at: installedPaths.redisRelayTargetPassword)
        case .missing:
            return
        case .inspectFailed(let reason):
            throw LauncherError.runtimeOperationFailed(
                "Redis relay password path inspection failed path=\(installedPaths.redisRelayTargetPassword.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw LauncherError.runtimeOperationFailed(
                "Redis relay password path state is unexpected path=\(installedPaths.redisRelayTargetPassword.path) state=\(fileStore.pathState(at: installedPaths.redisRelayTargetPassword).rawValue)"
            )
        }
    }

    private func runtimeRedisRelaySettings(
        _ settings: ConfigureRuntimeRedisRelaySettings,
        passwordConfigured: Bool
    ) -> RuntimeRedisRelaySettings {
        RuntimeRedisRelaySettings(
            enabled: settings.enabled,
            target: RuntimeRedisRelayTarget(
                url: settings.target.url,
                username: settings.target.username,
                password: "",
                clearPassword: false,
                passwordConfigured: passwordConfigured,
                tls: settings.target.tls
            ),
            scope: RuntimeRedisRelayScope(rawValue: settings.scope.rawValue) ?? .vitalReconstruction,
            includeRecorderNetworkContext: settings.includeRecorderNetworkContext,
            intervalSeconds: settings.intervalSeconds,
            scanCount: settings.scanCount
        )
    }

    private func writeRedisRelayTOML(settings: RuntimeRedisRelaySettings) throws {
        try requireRedisRelayPasswordFileIfConfigured(settings.target)
        try fileStore.writeData(
            Data(redisRelayTOML(settings).utf8),
            to: installedPaths.redisRelayConfig,
            options: .atomic
        )
    }

    private func requireRedisRelayPasswordFileIfConfigured(
        _ target: RuntimeRedisRelayTarget
    ) throws {
        guard target.passwordConfigured else {
            return
        }
        switch fileStore.pathState(at: installedPaths.redisRelayTargetPassword) {
        case .file:
            return
        case .missing:
            throw LauncherError.runtimeOperationFailed(
                "Redis relay password is configured but secret file is missing path=\(installedPaths.redisRelayTargetPassword.path)"
            )
        case .inspectFailed(let reason):
            throw LauncherError.runtimeOperationFailed(
                "Redis relay password path inspection failed path=\(installedPaths.redisRelayTargetPassword.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw LauncherError.runtimeOperationFailed(
                "Redis relay password path state is unexpected path=\(installedPaths.redisRelayTargetPassword.path) state=\(fileStore.pathState(at: installedPaths.redisRelayTargetPassword).rawValue)"
            )
        }
    }

    private func redisRelayTOML(_ settings: RuntimeRedisRelaySettings) -> String {
        var lines = [
            "[redis_relay]",
            "enabled = \(settings.enabled)",
            "scope = \"\(settings.scope.rawValue)\"",
            "include_recorder_network_context = \(settings.includeRecorderNetworkContext)",
            "interval_seconds = \(settings.intervalSeconds)",
            "scan_count = \(settings.scanCount)",
            "",
            "[source]",
            "host = \"redis\"",
            "port = 6379",
            "database = 0",
            "",
            "[target]",
            "url = \"\(tomlEscaped(redisRelayTargetURL(settings.target)))\"",
        ]
        if settings.target.passwordConfigured {
            lines.append("password_file = \"/run/tirosh/secrets/redis-relay-target-password\"")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func tomlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func redisRelayTargetURL(_ target: RuntimeRedisRelayTarget) -> String {
        guard var components = URLComponents(string: target.url) else {
            return target.url
        }
        components.scheme = target.tls ? "rediss" : "redis"
        components.user = target.username.isEmpty ? nil : target.username
        components.password = nil
        return components.string ?? target.url
    }
}
