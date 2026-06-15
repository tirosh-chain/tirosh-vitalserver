import Contracts
import Foundation

public struct RuntimeArtifactReplacementDestinations {
    public var managerApp: URL
    public var nginxBundle: URL
    public var guestDeploy: URL
    public var runtimeTools: URL

    public init(
        managerApp: URL,
        nginxBundle: URL,
        guestDeploy: URL,
        runtimeTools: URL
    ) {
        self.managerApp = managerApp
        self.nginxBundle = nginxBundle
        self.guestDeploy = guestDeploy
        self.runtimeTools = runtimeTools
    }
}

public struct RuntimeArtifactReplacementRules {
    public var tarCommand: String
    public var archiveLayout: UpdateBundleArtifactArchiveLayout

    public init(
        tarCommand: String,
        archiveLayout: UpdateBundleArtifactArchiveLayout = UpdateBundleArtifactArchiveLayouts.vitalServerHelper
    ) {
        self.tarCommand = tarCommand
        self.archiveLayout = archiveLayout
    }
}
