import HostAdapters
import XCTest

final class RuntimeInstallExecutablePreparerTests: XCTestCase {
    func testPrepareMarksInstalledExecutablesExecutableInOrder() throws {
        var events: [String] = []
        let preparer = RuntimeInstallExecutablePreparer(
            context: RuntimeInstallExecutablePreparationContext(
                executablePaths: [
                    "/usr/local/bin/vitalserver-vm",
                    "/usr/local/bin/vitalserver-proxy-run",
                    "/Library/Application Support/VitalServer/nginx/sbin/nginx",
                ],
                chmodExecutable: "/bin/chmod"
            ),
            operations: RuntimeInstallExecutablePreparationOperations(
                runRequired: { executable, arguments in
                    events.append("run:\(executable) \(arguments.joined(separator: " "))")
                }
            )
        )

        try preparer.prepare()

        XCTAssertEqual(events, [
            "run:/bin/chmod 0755 /usr/local/bin/vitalserver-vm",
            "run:/bin/chmod 0755 /usr/local/bin/vitalserver-proxy-run",
            "run:/bin/chmod 0755 /Library/Application Support/VitalServer/nginx/sbin/nginx",
        ])
    }
}
