import Foundation
import Errors

struct RuntimeArtifactArchiveValidator {
    var tarCommand: String
    var temporaryDirectory: URL
    var readUTF8Text: (URL) throws -> String
    var runProcessToFile: (String, [String], URL) throws -> Void
    var validateArchiveEntries: (String, String, String?, Set<String>?) throws -> Void
    var validateArchiveEntryTypes: (String, String) throws -> Void
    var archiveValidationFailureMessage: (Error, URL) -> String
    var validationOutputID: () -> String
    var removeTemporaryOutput: (URL) -> Void

    func validateTarGz(
        _ source: URL,
        requiredTopLevel: String? = nil,
        allowedRootEntries: Set<String>? = nil
    ) throws {
        let listOutput = temporaryDirectory
            .appendingPathComponent("tirosh-\(validationOutputID())-tar-list.txt")
        defer {
            removeTemporaryOutput(listOutput)
        }
        try runProcessToFile(tarCommand, ["-tzf", source.path], listOutput)
        do {
            try validateArchiveEntries(
                try readUTF8Text(listOutput),
                source.lastPathComponent,
                requiredTopLevel,
                allowedRootEntries
            )
        } catch {
            throw bundleVerificationFailure(archiveValidationFailureMessage(error, source))
        }

        let verboseOutput = temporaryDirectory
            .appendingPathComponent("tirosh-\(validationOutputID())-tar-verbose.txt")
        defer {
            removeTemporaryOutput(verboseOutput)
        }
        try runProcessToFile(tarCommand, ["-tvzf", source.path], verboseOutput)
        let verboseText = try readUTF8Text(verboseOutput)
        do {
            try validateArchiveEntryTypes(verboseText, source.lastPathComponent)
        } catch {
            throw bundleVerificationFailure(archiveValidationFailureMessage(error, source))
        }
    }

    private func bundleVerificationFailure(_ message: String) -> RuntimeArtifactReplacementError {
        .bundleVerificationFailed(message)
    }
}
