import Foundation
import Contracts
import RuntimeControl
import Errors

public extension AppConstants {
    enum Product {
        public static let displayName = "VitalServer Helper"
        public static let vitalDBName = "VitalDB"
        public static let vitalDBURL = "https://vitaldb.net"
        public static let poweredByPrefix = "Powered by"
        public static let tiroshName = "Tirosh"
        public static let tiroshURL = "https://www.tirosh.ai/"
        public static let packageIdentifier = "ai.tirosh.vitalserver.helper"
        public static let vitalServerVersion = GeneratedRelease.vitalServerVersion
        public static let defaultProxyPort = 80
        public static func vitalServerURL(proxyPort: Int) -> String {
            RuntimeSettingsInitialValues.vitalServerURL(proxyPort: proxyPort)
        }
        public static func remoteConsoleURL(port: Int) -> String {
            RuntimeSettingsInitialValues.remoteConsoleURL(runtimeControlPort: port)
        }
        public static func runtimeControlDevConsoleURL(port: Int) -> String {
            "http://127.0.0.1:\(port)/dev/runtime-control"
        }
        public static func runtimeControlPWAURL(port: Int) -> String {
            "http://127.0.0.1:\(port)/"
        }
        public static func redisUIURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/redis-ui/"
        }
        public static func swaggerURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/swagger/"
        }
        public static func hostProxyLivenessURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/health"
        }
        public static func hostProxyHealthURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/ready"
        }
        public static func guestHealthURL(vmIP: String) -> String {
            "http://\(vmIP)/ready"
        }
    }


}
