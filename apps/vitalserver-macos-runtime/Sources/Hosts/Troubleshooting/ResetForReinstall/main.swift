import Foundation

enum ResetForReinstallError: Error, CustomStringConvertible {
    case missingBundledRuntimeCLI(String)
    case launchFailed(String)

    var description: String {
        switch self {
        case .missingBundledRuntimeCLI(let path):
            return "bundled reset runtime CLI is missing or not executable: \(path)"
        case .launchFailed(let reason):
            return "failed to launch bundled reset runtime CLI: \(reason)"
        }
    }
}

func executableDirectory() -> URL {
    URL(fileURLWithPath: CommandLine.arguments[0])
        .standardizedFileURL
        .deletingLastPathComponent()
}

func run() throws -> Int32 {
    let runtimeCLI = executableDirectory()
        .appendingPathComponent("vitalserver-vm-reset-installer")
    guard FileManager.default.isExecutableFile(atPath: runtimeCLI.path) else {
        throw ResetForReinstallError.missingBundledRuntimeCLI(runtimeCLI.path)
    }

    let process = Process()
    process.executableURL = runtimeCLI
    process.arguments = ["runtime", "uninstall", "--force-clean-uninstaller"]
    do {
        try process.run()
    } catch {
        throw ResetForReinstallError.launchFailed(error.localizedDescription)
    }
    process.waitUntilExit()
    return process.terminationStatus
}

do {
    exit(try run())
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
