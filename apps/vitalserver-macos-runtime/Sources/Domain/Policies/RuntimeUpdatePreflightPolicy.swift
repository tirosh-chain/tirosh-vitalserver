import Contracts

public struct RuntimeUpdateStorageRequirement: Equatable, Sendable {
    public let requiredBytes: UInt64
    public let stagedBundleBytes: UInt64
    public let installedRootfsBytes: UInt64?
    public let incomingRootfsBytes: UInt64?

    public init(
        requiredBytes: UInt64,
        stagedBundleBytes: UInt64,
        installedRootfsBytes: UInt64?,
        incomingRootfsBytes: UInt64?
    ) {
        self.requiredBytes = requiredBytes
        self.stagedBundleBytes = stagedBundleBytes
        self.installedRootfsBytes = installedRootfsBytes
        self.incomingRootfsBytes = incomingRootfsBytes
    }
}

public enum RuntimeUpdateRootfsStorageInput: Equatable, Sendable {
    case unchanged
    case replacing(installedRootfsBytes: UInt64, incomingRootfsBytes: UInt64)
}

public enum RuntimeUpdatePreflightPolicy {
    public static func checkCompatibility(
        manifest: UpdateBundleManifest,
        currentChannel: UpdateBundleChannel,
        currentPlatform: String?
    ) throws {
        try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest,
            currentChannel: currentChannel,
            currentPlatform: currentPlatform
        )
    }

    public static func storageRequirement(
        stagedBundleBytes: UInt64,
        rootfsStorage: RuntimeUpdateRootfsStorageInput,
        marginBytes: UInt64
    ) -> RuntimeUpdateStorageRequirement {
        let installedRootfsBytes: UInt64?
        let incomingRootfsBytes: UInt64?
        let rootfsBytes: UInt64
        switch rootfsStorage {
        case .unchanged:
            installedRootfsBytes = nil
            incomingRootfsBytes = nil
            rootfsBytes = 0
        case .replacing(let installed, let incoming):
            installedRootfsBytes = installed
            incomingRootfsBytes = incoming
            rootfsBytes = installed + incoming
        }
        return RuntimeUpdateStorageRequirement(
            requiredBytes: marginBytes + stagedBundleBytes + rootfsBytes,
            stagedBundleBytes: stagedBundleBytes,
            installedRootfsBytes: installedRootfsBytes,
            incomingRootfsBytes: incomingRootfsBytes
        )
    }

    public static func blockingGuestStorageErrors(_ errors: [RuntimeVMError]) -> [RuntimeVMError] {
        errors.filter { error in
            switch error {
            case .diskAttachmentInvalid, .guestFilesystemError, .guestFilesystemReadOnly, .guestDiskIO:
                return true
            default:
                return false
            }
        }
    }
}
