import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
protocol RuntimeNativeShell {
    func chooseDirectory(prompt: String) -> URL?
    func chooseUpdateBundle(prompt: String) -> URL?
    func chooseLogExportDestination(defaultName: String, prompt: String) -> URL?
    func directoryExists(_ url: URL) -> Bool
    func confirmCreateDirectory(path: String) -> Bool
    func createDirectory(_ url: URL) throws
    func openFileURL(_ url: URL)
    func openWebURL(_ url: URL)
    func relaunchHelper()
    func terminate()
}

@MainActor
struct SystemRuntimeNativeShell: RuntimeNativeShell {
    func chooseDirectory(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        let delegate = VitalFilesDirectoryOpenPanelDelegate()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.delegate = delegate
        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }

    func chooseUpdateBundle(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "tar.gz"),
            UTType(filenameExtension: "tgz"),
            .gzip,
        ].compactMap { $0 }
        panel.prompt = prompt
        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }

    func chooseLogExportDestination(defaultName: String, prompt: String) -> URL? {
        let panel = NSSavePanel()
        let delegate = LogExportSavePanelDelegate()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = defaultName
        panel.prompt = prompt
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.delegate = delegate
        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }

    func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    func confirmCreateDirectory(path: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = AppConstants.StatusText.folderMissingTitle
        alert.informativeText = AppConstants.StatusText.folderMissingCreateQuestion(path: path)
        alert.alertStyle = .informational
        alert.addButton(withTitle: AppConstants.Actions.createFolder)
        alert.addButton(withTitle: AppConstants.Actions.cancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    func createDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            try createDirectoryWithAdministratorPrivileges(url)
        }
    }

    func openFileURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func openWebURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func relaunchHelper() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: NativeShellConstants.Commands.open)
        process.arguments = ["-n", Bundle.main.bundleURL.path]
        try? process.run()
        terminate()
    }

    func terminate() {
        NSApplication.shared.terminate(nil)
    }

    private func createDirectoryWithAdministratorPrivileges(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \(appleScriptString("/bin/mkdir -p -- \(shellQuoted(url.path))")) with administrator privileges",
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

private final class VitalFilesDirectoryOpenPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    private let policy = RuntimeVitalFilesDirectoryPolicy()

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        policy.isAllowed(url)
    }

    func panel(_ sender: Any, validate url: URL) throws {
        if let message = policy.validationMessage(for: url) {
            throw NSError(
                domain: "VitalServerHelper.VitalFilesDirectory",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}

private final class LogExportSavePanelDelegate: NSObject, NSOpenSavePanelDelegate {
    private let policy = RuntimeLogExportDestinationPolicy()

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return true
        }
        return policy.canNavigateDirectory(url)
    }

    func panel(_ sender: Any, validate url: URL) throws {
        if let message = policy.validationMessage(for: url) {
            throw NSError(
                domain: "VitalServerHelper.LogExportDestination",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}
