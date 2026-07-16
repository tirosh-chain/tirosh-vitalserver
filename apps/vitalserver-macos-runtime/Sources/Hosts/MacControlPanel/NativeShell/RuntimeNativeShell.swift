import AppKit
import Foundation
import UniformTypeIdentifiers
import Contracts
import InboundAdapters
import Errors

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

    func chooseRedisBackupArchive(prompt: String) -> URL? {
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

    func chooseVitalFiles(prompt: String, directoryURL: URL?) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = directoryURL
        panel.allowedContentTypes = [
            UTType(filenameExtension: "vital"),
        ].compactMap { $0 }
        panel.prompt = prompt
        guard panel.runModal() == .OK else {
            return []
        }
        return panel.urls
    }

    func readVitalFileUploadSources(
        _ sources: [URL]
    ) throws -> [RuntimeLabVitalFileUploadSource] {
        guard !sources.isEmpty else {
            throw vitalFileImportError("Select at least one .vital file.")
        }
        let normalizedSources = sources.map(\.standardizedFileURL)
        for source in normalizedSources {
            let values = try source.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                throw vitalFileImportError("Upload source is not a regular file: \(source.path)")
            }
        }

        return try normalizedSources.map { source in
            let accessed = source.startAccessingSecurityScopedResource()
            defer {
                if accessed { source.stopAccessingSecurityScopedResource() }
            }
            return RuntimeLabVitalFileUploadSource(
                fileName: source.lastPathComponent,
                content: try Data(contentsOf: source, options: .mappedIfSafe)
            )
        }
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

    func logExportDestinationValidationMessage(for url: URL) -> String? {
        RuntimeLogExportDestinationPolicy().validationMessage(for: url)
    }

    func pathState(_ url: URL) -> RuntimePathState {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let type = attributes[.type] as? FileAttributeType else {
                return .other("missing-file-type")
            }
            switch type {
            case .typeRegular:
                return .file
            case .typeDirectory:
                return .directory
            default:
                return .other(type.rawValue)
            }
        } catch {
            return isNoSuchFile(error) ? .missing : .inspectFailed(error.localizedDescription)
        }
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

    func copyFile(_ source: URL, to destination: URL) throws {
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            try copyFileWithAdministratorPrivileges(source, to: destination)
        }
    }

    func copyDirectory(_ source: URL, to destination: URL) throws {
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            try copyDirectoryWithAdministratorPrivileges(source, to: destination)
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

    private func copyFileWithAdministratorPrivileges(_ source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \(appleScriptString("/bin/cp \(shellQuoted(source.path)) \(shellQuoted(destination.path))")) with administrator privileges",
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    private func copyDirectoryWithAdministratorPrivileges(_ source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \(appleScriptString("/bin/cp -R \(shellQuoted(source.path)) \(shellQuoted(destination.path))")) with administrator privileges",
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

    private func isNoSuchFile(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.Code.fileReadNoSuchFile.rawValue {
            return true
        }
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)
    }
}

private func vitalFileImportError(_ message: String) -> NSError {
    NSError(
        domain: "VitalFileLibraryImport",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: message]
    )
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
        switch FileManager.default.pathState(atPath: url.path) {
        case .directory:
            return policy.canNavigateDirectory(url)
        case .inspectFailed:
            return false
        case .file, .missing, .other, .unknown:
            return true
        }
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
