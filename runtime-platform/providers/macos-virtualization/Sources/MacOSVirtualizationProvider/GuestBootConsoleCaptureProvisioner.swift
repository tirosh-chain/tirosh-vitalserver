import Foundation

// GuestBootConsoleCaptureProvisioner is the macOS Host filesystem adapter for
// the C32-declared append-only diagnostic capture. The Guest never owns this
// file: it is a Host-side record of serial output and is not Guest readiness
// or a substitute for a Guest-owned receipt.
public enum GuestBootConsoleCaptureProvisioningOutcome: String, Equatable, Sendable {
    case created
    case retainedExistingAppendOnlyCapture = "retained-existing-append-only-capture"
}

public enum GuestBootConsoleCaptureProvisioningError: LocalizedError {
    case unavailable(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message), .failed(let message):
            message
        }
    }
}

public enum GuestBootConsoleCaptureProvisioner {
    // provision creates only the C32-declared parent directory and empty
    // capture file. It never truncates, rotates, or parses prior Guest output.
    public static func provision(
        capture: GuestBootConsoleCapture
    ) throws -> GuestBootConsoleCaptureProvisioningOutcome {
        if let validationMessage = capture.validationMessage {
            throw GuestBootConsoleCaptureProvisioningError.failed(
                "Guest boot console capture configuration is invalid: \(validationMessage)"
            )
        }
        let captureURL = URL(fileURLWithPath: capture.capturePath)
        let fileManager = FileManager.default
        let captureDirectoryURL = captureURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: captureDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw GuestBootConsoleCaptureProvisioningError.unavailable(
                "Guest boot console capture directory cannot be created: \(error.localizedDescription)"
            )
        }

        if fileManager.fileExists(atPath: captureURL.path) {
            try requireRegularGuestBootConsoleCapture(captureURL)
            return .retainedExistingAppendOnlyCapture
        }

        guard fileManager.createFile(
            atPath: captureURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            // A concurrent Host provision may have created the declared file
            // between fileExists and createFile. It is safe only after the
            // same regular-file check; a directory or symlink never becomes
            // a diagnostic capture by fallback.
            try requireRegularGuestBootConsoleCapture(captureURL)
            return .retainedExistingAppendOnlyCapture
        }
        try requireRegularGuestBootConsoleCapture(captureURL)
        return .created
    }

    private static func requireRegularGuestBootConsoleCapture(_ captureURL: URL) throws {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: captureURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw GuestBootConsoleCaptureProvisioningError.failed(
                    "Guest boot console capture must be a regular file"
                )
            }
        } catch let error as GuestBootConsoleCaptureProvisioningError {
            throw error
        } catch {
            throw GuestBootConsoleCaptureProvisioningError.unavailable(
                "Guest boot console capture cannot be read"
            )
        }
    }
}
