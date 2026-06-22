import Foundation
import RuntimeControl
import Errors

public extension RuntimeReleaseInfo {
    static var generated: RuntimeReleaseInfo {
        var services = [
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.vitalServerName,
                image: GeneratedRelease.vitalServerImage,
                version: GeneratedRelease.vitalServerVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.auditProxyName,
                image: GeneratedRelease.auditProxyImage,
                version: GeneratedRelease.auditProxyVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.vitalDBObserverName,
                image: GeneratedRelease.vitalDBObserverImage,
                version: GeneratedRelease.vitalDBObserverVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.redisRelayName,
                image: GeneratedRelease.redisRelayImage,
                version: GeneratedRelease.redisRelayVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.redisName,
                image: GeneratedRelease.redisImage,
                version: GeneratedRelease.redisVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.redisUIName,
                image: GeneratedRelease.redisUIImage,
                version: GeneratedRelease.redisUIVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.swaggerUIName,
                image: GeneratedRelease.swaggerUIImage,
                version: GeneratedRelease.swaggerUIVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.guestEdgeName,
                image: GeneratedRelease.guestEdgeImage,
                version: GeneratedRelease.guestEdgeVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.hostProxyName,
                image: GeneratedRelease.hostProxyImage,
                version: GeneratedRelease.hostProxyVersion
            ),
        ]
        if GeneratedRelease.testkitContainerIncluded {
            services.append(RuntimeBundledServiceInfo(
                name: GeneratedRelease.testkitName,
                image: GeneratedRelease.testkitImage,
                version: GeneratedRelease.testkitVersion
            ))
        }
        return RuntimeReleaseInfo(
            helperVersion: GeneratedRelease.helperVersion,
            minimumUpdaterVersion: GeneratedRelease.minUpdaterVersion,
            vitalServerVersion: GeneratedRelease.vitalServerVersion,
            services: services
        )
    }
}
