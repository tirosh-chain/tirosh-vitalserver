import Foundation

struct RuntimeSettings {
    var cpuCount = 8
    var memoryGiB = 8
    var networkMode = "shared"
    var bridgedInterface = ""
    var proxyPort = AppConstants.Product.defaultProxyPort
    var vitalFilesDirectory = "/Library/Application Support/TiroshVitalServer/vm/data/vital-files"
    var publicHost = ""
    var publicPort = 80
    var adminPassword = ""
    var changeAdminPassword = false
    var startOnBoot = true
    var startOnBootConfigurable = true
    var restartAfterSave = true

    static func load() -> RuntimeSettings {
        var settings = RuntimeSettings()

        if let vmConfig = VMConfigDocument.load(path: AppConstants.Paths.vmConfig) {
            settings.cpuCount = vmConfig.cpuCount
            settings.memoryGiB = max(Int(vmConfig.memoryMiB / 1024), 1)
            settings.networkMode = vmConfig.network.mode
            settings.bridgedInterface = vmConfig.network.bridgedInterface ?? ""
            if let vitalFilesDirectory = vmConfig.vitalFilesDirectory?.hostPath {
                settings.vitalFilesDirectory = vitalFilesDirectory
            }
        }

        if let guestConfig = GuestRuntimeConfig.load(path: AppConstants.Paths.guestRuntimeConfig) {
            settings.publicHost = guestConfig.publicHost
            settings.publicPort = guestConfig.publicPort
        }

        settings.proxyPort = RuntimeStatus.load(paths: RuntimePaths()).proxyPort
        if let startOnBoot = startOnBootEnabled() {
            settings.startOnBoot = startOnBoot
            settings.startOnBootConfigurable = true
        } else {
            settings.startOnBootConfigurable = false
        }
        return settings
    }

    func configureArguments(adminPasswordFile: String? = nil) -> [String] {
        var arguments = [
            "runtime",
            "configure",
            "--cpu",
            String(cpuCount),
            "--memory-gib",
            String(memoryGiB),
            "--network",
            networkMode,
            "--proxy-port",
            String(proxyPort),
            "--vital-files-dir",
            vitalFilesDirectory,
            "--public-host",
            publicHost,
            "--public-port",
            String(publicPort),
        ]
        if startOnBootConfigurable {
            arguments += [
                "--start-on-boot",
                startOnBoot ? "true" : "false",
            ]
        }
        if networkMode == "bridged", !bridgedInterface.isEmpty {
            arguments += ["--bridged-interface", bridgedInterface]
        }
        if let adminPasswordFile {
            arguments += ["--admin-password-file", adminPasswordFile]
        }
        if restartAfterSave {
            arguments.append("--restart")
        }
        return arguments
    }

    private static func startOnBootEnabled() -> Bool? {
        let result = ProcessRunner.runSync(
            AppConstants.Commands.launchctl,
            arguments: ["print-disabled", "system"]
        )
        guard result.exitCode == 0 else {
            return nil
        }
        let output = result.stdout
        for label in [
            AppConstants.Launchd.vmService,
            AppConstants.Launchd.proxyService,
            AppConstants.Launchd.watchdogService,
        ] where output.contains("\"\(label)\" => true") {
            return false
        }
        return true
    }
}

private struct VMConfigDocument: Decodable {
    let cpuCount: Int
    let memoryMiB: UInt64
    let network: NetworkDocument
    let vitalFilesDirectory: SharedDirectoryDocument?

    static func load(path: String) -> VMConfigDocument? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return try? JSONDecoder().decode(VMConfigDocument.self, from: data)
    }
}

private struct NetworkDocument: Decodable {
    let mode: String
    let bridgedInterface: String?
}

private struct SharedDirectoryDocument: Decodable {
    let hostPath: String
}

private struct GuestRuntimeConfig: Decodable {
    let publicHost: String
    let publicPort: Int

    static func load(path: String) -> GuestRuntimeConfig? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return try? JSONDecoder().decode(GuestRuntimeConfig.self, from: data)
    }
}
