import Foundation
import Application
import Contracts

public struct RuntimeGuestConfigWriter {
    private let installedPaths: InstalledRuntimePaths
    private let fileStore: RuntimeFileStore
    private let restrictSecretFile: (URL) throws -> Void

    public init(
        installedPaths: InstalledRuntimePaths,
        fileStore: RuntimeFileStore,
        restrictSecretFile: @escaping (URL) throws -> Void
    ) {
        self.installedPaths = installedPaths
        self.fileStore = fileStore
        self.restrictSecretFile = restrictSecretFile
    }

    public func write(runtimeConfig: GuestRuntimeConfigDocument) throws {
        let runtimeConfigURL = installedPaths.guestRuntimeConfig
        try fileStore.writeData(
            try runtimeGuestConfigDocumentEncoder().encode(runtimeConfig),
            to: runtimeConfigURL,
            options: .atomic
        )
        try writeSettings(runtimeConfig)
        try restrictSecretFile(runtimeConfigURL)
    }

    private func writeSettings(_ runtimeConfig: GuestRuntimeConfigDocument) throws {
        let document = GuestRuntimeSettingsDocument(runtimeConfig: runtimeConfig)
        try fileStore.writeData(
            try runtimeGuestConfigDocumentEncoder().encode(document),
            to: installedPaths.guestRuntimeSettings,
            options: .atomic
        )
    }
}

private func runtimeGuestConfigDocumentEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}
