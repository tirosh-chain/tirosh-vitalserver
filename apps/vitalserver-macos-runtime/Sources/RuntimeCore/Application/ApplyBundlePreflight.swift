import RuntimeContracts
import Foundation

public struct RuntimeServiceRestartPolicy: Equatable, Sendable {
    public let restartVM: Bool
    public let restartProxy: Bool
    public let restartWatchdog: Bool

    public init(restartVM: Bool, restartProxy: Bool, restartWatchdog: Bool) {
        self.restartVM = restartVM
        self.restartProxy = restartProxy
        self.restartWatchdog = restartWatchdog
    }

    public var anyServiceWasRunning: Bool {
        restartVM || restartProxy || restartWatchdog
    }
}

public struct ApplyBundlePreflightContext: Equatable, Sendable {
    public let stagedBundle: URL
    public let manifest: UpdateBundleManifest
    public let stagedRootfs: URL?
    public let backup: URL
    public let restartPolicy: RuntimeServiceRestartPolicy
    public var updatesRootfsBase: Bool {
        stagedRootfs != nil
    }

    public init(
        stagedBundle: URL,
        manifest: UpdateBundleManifest,
        stagedRootfs: URL?,
        backup: URL,
        restartPolicy: RuntimeServiceRestartPolicy
    ) {
        self.stagedBundle = stagedBundle
        self.manifest = manifest
        self.stagedRootfs = stagedRootfs
        self.backup = backup
        self.restartPolicy = restartPolicy
    }
}
