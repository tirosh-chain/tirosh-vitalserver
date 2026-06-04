import Foundation
@testable import HostCLI
import XCTest

final class RuntimeInstallPermissionConfiguratorTests: XCTestCase {
    func testConfigureAppliesOwnershipProxyPortAndPlistPermissionsInOrder() throws {
        let events = EventLog()
        let configurator = RuntimeInstallPermissionConfigurator(
            context: RuntimeInstallPermissionContext(
                runtimeHome: URL(fileURLWithPath: "/Library/Application Support/VitalServer"),
                nginxDirectory: URL(fileURLWithPath: "/Library/Application Support/VitalServer/nginx"),
                proxyLaunchDaemonPlist: "/Library/LaunchDaemons/proxy.plist",
                serviceLaunchDaemonPlists: [
                    "/Library/LaunchDaemons/vm.plist",
                    "/Library/LaunchDaemons/proxy.plist",
                    "/Library/LaunchDaemons/guest-log-sync.plist",
                ],
                chownExecutable: "/usr/sbin/chown",
                chmodExecutable: "/bin/chmod",
                plistBuddyExecutable: "/usr/libexec/PlistBuddy"
            ),
            operations: RuntimeInstallPermissionOperations(
                runRequired: { executable, arguments in
                    events.append("run:\(executable) \(arguments.joined(separator: " "))")
                }
            )
        )

        try configurator.configure(input: RuntimeInstallPermissionInput(proxyPort: 18443))

        XCTAssertEqual(events.values, [
            "run:/usr/sbin/chown -R root:wheel /Library/Application Support/VitalServer",
            "run:/usr/sbin/chown -R root:wheel /Library/Application Support/VitalServer/nginx",
            "run:/usr/libexec/PlistBuddy -c Set :EnvironmentVariables:VITALSERVER_PROXY_PORT 18443 /Library/LaunchDaemons/proxy.plist",
            "run:/bin/chmod 0644 /Library/LaunchDaemons/vm.plist",
            "run:/usr/sbin/chown root:wheel /Library/LaunchDaemons/vm.plist",
            "run:/bin/chmod 0644 /Library/LaunchDaemons/proxy.plist",
            "run:/usr/sbin/chown root:wheel /Library/LaunchDaemons/proxy.plist",
            "run:/bin/chmod 0644 /Library/LaunchDaemons/guest-log-sync.plist",
            "run:/usr/sbin/chown root:wheel /Library/LaunchDaemons/guest-log-sync.plist",
        ])
    }

    private final class EventLog {
        private(set) var values: [String] = []

        func append(_ value: String) {
            values.append(value)
        }
    }
}
