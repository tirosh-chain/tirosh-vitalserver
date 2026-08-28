import Application
import Contracts
import Domain
import Foundation
import OutboundAdapters

public struct SystemPlatformAgentUpdateBootstrapSelectionOwner:
    PlatformAgentUpdateBootstrapSelectionOwning,
    @unchecked Sendable
{
    private let installedPaths: InstalledRuntimePaths
    private let fileStore: RuntimeFileStore
    private let clock: any RuntimeClock
    private let generateSelectionId: @Sendable () -> String

    public init(
        installedPaths: InstalledRuntimePaths = .defaultInstalled,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        clock: any RuntimeClock = SystemRuntimeClock(),
        generateSelectionId: @escaping @Sendable () -> String = {
            UUID().uuidString.lowercased()
        }
    ) {
        self.installedPaths = installedPaths
        self.fileStore = fileStore
        self.clock = clock
        self.generateSelectionId = generateSelectionId
    }

    public func recordVerifiedSelection(
        verificationInvocationId: String,
        updateId: String,
        canonicalPayloadSHA256: String,
        observedBundlePath: String,
        observedAt: String
    ) throws {
        _ = try RecordPlatformAgentUpdateBootstrapVerifiedSelectionUseCase()
            .record(
                selectionId: generateSelectionId(),
                verificationInvocationId: verificationInvocationId,
                updateId: updateId,
                canonicalPayloadSHA256: canonicalPayloadSHA256,
                observedBundlePath: observedBundlePath,
                observedAt: observedAt,
                currentRead: selectionReader().read(at: storeURL),
                persist: persistSelection
            )
    }

    public func bindApply(
        observedBundlePath: String,
        mintRequestId: @Sendable () -> String
    ) throws -> String {
        try BindPlatformAgentUpdateBootstrapApplyUseCase().bind(
            observedBundlePath: observedBundlePath,
            mintRequestId: mintRequestId,
            observedAt: timestamp(),
            currentRead: selectionReader().read(at: storeURL),
            persist: persistSelection
        )
    }

    public func spendApply(requestId: String) throws {
        try SpendPlatformAgentUpdateBootstrapApplyUseCase().spend(
            requestId: requestId,
            observedAt: timestamp(),
            currentRead: selectionReader().read(at: storeURL),
            persist: persistSelection
        )
    }

    private var storeURL: URL {
        installedPaths.platformAgentUpdateBootstrapVerifiedSelection
    }

    private func timestamp() -> String {
        UpdateBootstrapCanonicalTimestampSyntax.format(clock.now)
    }

    private func persistSelection(
        _ selection: PlatformAgentUpdateBootstrapVerifiedSelection
    ) throws {
        try selectionWriter().write(selection, to: storeURL)
    }

    private func selectionWriter() -> PlatformAgentUpdateBootstrapVerifiedSelectionWriter {
        PlatformAgentUpdateBootstrapVerifiedSelectionWriter(
            operations:
                PlatformAgentUpdateBootstrapVerifiedSelectionWriteOperations(
                    pathState: fileStore.pathState,
                    createDirectory: fileStore.createDirectory,
                    writeData: { data, url, options in
                        try fileStore.writeData(data, to: url, options: options)
                    },
                    validate:
                        PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
                        .validate
                )
        )
    }

    private func selectionReader() -> PlatformAgentUpdateBootstrapVerifiedSelectionReader {
        PlatformAgentUpdateBootstrapVerifiedSelectionReader(
            pathState: fileStore.pathState,
            readData: fileStore.readData
        )
    }
}
