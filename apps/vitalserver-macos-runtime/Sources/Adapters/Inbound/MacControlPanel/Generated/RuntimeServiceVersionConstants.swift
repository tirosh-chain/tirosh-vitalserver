import Errors
extension AppConstants {
    enum ServiceVersions {
        static let vitalServerImage = GeneratedRelease.vitalServerImage
        static let redisImage = GeneratedRelease.redisImage
        static let postgresImage = GeneratedRelease.postgresImage
        static let redisUIImage = GeneratedRelease.redisUIImage
        static let swaggerUIImage = GeneratedRelease.swaggerUIImage
        static let guestEdgeImage = GeneratedRelease.guestEdgeImage
        static let hostProxy = GeneratedRelease.hostProxyImage
        static let redisVersion = GeneratedRelease.redisVersion
        static let postgresVersion = GeneratedRelease.postgresVersion
        static let redisUIVersion = GeneratedRelease.redisUIVersion
        static let swaggerUIVersion = GeneratedRelease.swaggerUIVersion
        static let guestEdgeVersion = GeneratedRelease.guestEdgeVersion
        static let hostProxyVersion = GeneratedRelease.hostProxyVersion
    }
}
