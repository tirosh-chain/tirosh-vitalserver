import AppKit
import Foundation

@MainActor
final class InstallerController: ObservableObject {
    @Published var settings = InstallerSettings()
    @Published var message = "Ready"
    @Published var isBusy = false

    private let settingsPath = "/private/tmp/tirosh-vitalserver-install.json"
    private let packageName = "Install Tirosh VitalServer.pkg"

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
            let packageURL = try resolvePackageURL()
            try writeSettings()
            message = "Waiting for administrator approval..."
            let command = "installer -pkg \(shellQuote(packageURL.path)) -target /"
            let script = #"do shell script "\#(appleScriptEscaped(command))" with administrator privileges"#
            let result = await ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", script])
            if result.exitCode == 0 {
                message = "Installation completed."
            } else {
                let output = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                message = output.isEmpty ? "Installation was cancelled or failed." : output
            }
        } catch {
            message = "\(error)"
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
