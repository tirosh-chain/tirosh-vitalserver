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
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
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
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = defaultName
        panel.prompt = prompt
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
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
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
}
