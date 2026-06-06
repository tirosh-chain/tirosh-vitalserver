import Foundation

public enum RuntimeClientError: LocalizedError {
    case missingLauncher
    case missingUninstaller
    case logExportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingLauncher:
            return "vitalserver-vm launcher is missing. Reinstall the app or package."
        case .missingUninstaller:
            return "Uninstaller is missing. Reinstall the package before uninstalling."
        case .logExportFailed(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Log export failed." : trimmed
        }
    }
}
