import Foundation
import Management

extension RuntimeReleaseInfo {
    static let generated = RuntimeReleaseInfo(
        helperVersion: GeneratedRelease.helperVersion,
        minimumUpdaterVersion: GeneratedRelease.minUpdaterVersion,
        vitalServerVersion: GeneratedRelease.vitalServerVersion,
        services: [
            RuntimeBundledServiceInfo(
                name: AppConstants.Labels.vitalServer,
                image: GeneratedRelease.vitalServerImage,
                version: GeneratedRelease.vitalServerVersion
            ),
            RuntimeBundledServiceInfo(
                name: AppConstants.Labels.redis,
                image: GeneratedRelease.redisImage,
                version: GeneratedRelease.redisVersion
            ),
            RuntimeBundledServiceInfo(
                name: AppConstants.Labels.redisUI,
                image: GeneratedRelease.redisUIImage,
                version: GeneratedRelease.redisUIVersion
            ),
            RuntimeBundledServiceInfo(
                name: AppConstants.Labels.swaggerUI,
                image: GeneratedRelease.swaggerUIImage,
                version: GeneratedRelease.swaggerUIVersion
            ),
            RuntimeBundledServiceInfo(
                name: AppConstants.Labels.guestEdgeProxy,
                image: GeneratedRelease.guestEdgeImage,
                version: GeneratedRelease.guestEdgeVersion
            ),
            RuntimeBundledServiceInfo(
                name: AppConstants.Labels.hostProxyService,
                image: GeneratedRelease.hostProxyImage,
                version: GeneratedRelease.hostProxyVersion
            ),
        ]
    )
}
