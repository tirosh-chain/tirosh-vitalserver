import AppKit
import Foundation

@MainActor
final class InstallerController: ObservableObject {
    @Published var settings = InstallerSettings()
    @Published var message = "Ready"
    @Published var stage = "Ready"
    @Published var validationIssues: [String] = []
    @Published var isBusy = false

    private let settingsPath = "/private/tmp/tirosh-vitalserver-install.json"
    private let packageName = "Install Tirosh VitalServer.pkg"
    private let installLog = "/Library/Application Support/TiroshVitalServer/logs/install.log"
    private let installFreeSpaceMarginBytes: UInt64 = 4 * 1024 * 1024 * 1024

    func chooseVitalFilesDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Directory"
        if panel.runModal() == .OK, let url = panel.url {
            settings.vitalFilesDirectory = url.path
        }
    }

    func install() async {
        isBusy = true
        defer { isBusy = false }

        do {
            stage = "Preparing"
            let packageURL = try resolvePackageURL()
            validationIssues = validate(packageURL: packageURL)
            guard validationIssues.isEmpty else {
                message = validationIssues.joined(separator: "\n")
                stage = "Fix settings"
                return
            }
            try writeSettings()
            defer {
                cleanupSettingsFile()
            }
            let logTask = Task { await followInstallLog() }
            defer { logTask.cancel() }
            message = "Waiting for administrator approval..."
            stage = "Waiting for administrator approval"
            let command = "installer -pkg \(shellQuote(packageURL.path)) -target /"
            let script = #"do shell script "\#(appleScriptEscaped(command))" with administrator privileges"#
            let result = await ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", script])
            if result.exitCode == 0 {
                stage = "Completed"
                message = "Installation completed."
            } else {
                stage = "Failed"
                let output = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                message = output.isEmpty ? "Installation was cancelled or failed." : output
            }
        } catch {
            stage = "Failed"
            message = "\(error)"
        }
    }

    func openInstallLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: installLog))
    }

    func revalidate() {
        validationIssues = validate(packageURL: try? resolvePackageURL())
        if validationIssues.isEmpty {
            message = "Settings look valid."
            stage = "Ready"
        } else {
            message = validationIssues.joined(separator: "\n")
            stage = "Fix settings"
        }
    }

    private func resolvePackageURL() throws -> URL {
        let bundleRoot = Bundle.main.bundleURL.deletingLastPathComponent()
        let sibling = bundleRoot.appendingPathComponent(packageName)
        if FileManager.default.fileExists(atPath: sibling.path) {
            return sibling
        }
        throw InstallerError.missingPackage(sibling.path)
    }

    private func writeSettings() throws {
        let data = try JSONEncoder.installerPretty.encode(settings)
        try data.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: settingsPath
        )
        message = "Wrote install settings: \(settingsPath)"
    }

    private func cleanupSettingsFile() {
        try? FileManager.default.removeItem(atPath: settingsPath)
    }

    private func validate(packageURL: URL?) -> [String] {
        var issues: [String] = []
        if !settings.vitalFilesDirectory.hasPrefix("/") {
            issues.append("Vital files directory must be an absolute path.")
        }
        if settings.networkMode != "shared", settings.networkMode != "bridged" {
            issues.append("Network must be shared or bridged.")
        }
        if settings.vmHostname.isEmpty || settings.vmHostname.count > 63 {
            issues.append("VM hostname must be 1-63 characters.")
        }
        if settings.vmHostname.contains("\n") || settings.vmHostname.contains("\r") {
            issues.append("VM hostname must not contain newlines.")
        }
        if settings.publicHost.contains("\n") || settings.publicHost.contains("\r") {
            issues.append("Public host must not contain newlines.")
        }
        if settings.adminPassword.isEmpty {
            issues.append("Admin password must not be empty.")
        }
        if !portAvailable(settings.proxyPort) {
            issues.append("Proxy port \(settings.proxyPort) is already in use.")
        }
        if availableBytes(at: "/Library/Application Support") < requiredInstallBytes(packageURL: packageURL) {
            issues.append("Not enough free disk space under /Library/Application Support for the selected disk/rootfs/update policy.")
        }
        return issues
    }

    private func requiredInstallBytes(packageURL: URL?) -> UInt64 {
        let gib = UInt64(settings.diskGiB) * 1024 * 1024 * 1024
        let packageBytes = packageURL.flatMap { fileSize(at: $0.path) } ?? 0
        return packageBytes + (gib / 4) + installFreeSpaceMarginBytes
    }

    private func availableBytes(at path: String) -> UInt64 {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path),
              let value = attributes[.systemFreeSize] as? NSNumber else {
            return 0
        }
        return value.uint64Value
    }

    private func fileSize(at path: String) -> UInt64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let value = attributes[.size] as? NSNumber else {
            return 0
        }
        return value.uint64Value
    }

    private func portAvailable(_ port: Int) -> Bool {
        let result = ProcessRunner.runSync("/usr/sbin/lsof", arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"])
        return result.exitCode != 0
    }

    private func followInstallLog() async {
        while !Task.isCancelled {
            if let text = try? String(contentsOfFile: installLog, encoding: .utf8) {
                let lines = text.split(separator: "\n").suffix(20).joined(separator: "\n")
                if !lines.isEmpty {
                    message = lines
                    updateStage(from: lines)
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func updateStage(from logTail: String) {
        if logTail.contains("provision-vm-disk") {
            stage = "Creating VM disk"
        } else if logTail.contains("create-cloud-init-seed") {
            stage = "Creating VM boot seed"
        } else if logTail.contains("start-installed-services") {
            stage = "Starting services"
        } else if logTail.contains("runtime install completed") {
            stage = "Completed"
        } else if logTail.contains("status=failed") || logTail.contains("postinstall failed") {
            stage = "Failed"
        } else if logTail.contains("runtime install started") {
            stage = "Installing runtime"
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum InstallerError: Error, CustomStringConvertible {
    case missingPackage(String)

    var description: String {
        switch self {
        case let .missingPackage(path):
            return "Missing package: \(path)"
        }
    }
}
