import Contracts
import Foundation
import OutboundAdapters
import XCTest
import Errors

final class RuntimeMigrationRunnerTests: XCTestCase {
    func testRunSkipsEmptyMigrationList() throws {
        var logs: [String] = []
        let runner = RuntimeMigrationRunner(
            executableState: { _ in
                XCTFail("should not check executable files")
                return .missing
            },
            runRequired: { _, _ in XCTFail("should not run migrations") },
            log: { logs.append($0) }
        )

        try runner.run([], stagedBundle: URL(fileURLWithPath: "/bundle"))

        XCTAssertEqual(logs, ["no migrations to run"])
    }

    func testRunExecutesMigrationsInOrder() throws {
        let stagedBundle = URL(fileURLWithPath: "/bundle")
        var events: [String] = []
        let runner = RuntimeMigrationRunner(
            executableState: { path in
                events.append("executable:\(path)")
                return .executable
            },
            runRequired: { path, arguments in
                events.append("run:\(path):\(arguments.joined(separator: ","))")
            },
            log: { message in events.append("log:\(message)") }
        )

        try runner.run([
            UpdateBundleMigration(name: "001-refresh", sha256: "abc", size: 10),
            UpdateBundleMigration(name: "002-repair", sha256: "def", size: 20),
        ], stagedBundle: stagedBundle)

        XCTAssertEqual(events, [
            "executable:/bundle/migrations/001-refresh",
            "log:running migration name=001-refresh path=/bundle/migrations/001-refresh",
            "run:/bundle/migrations/001-refresh:",
            "executable:/bundle/migrations/002-repair",
            "log:running migration name=002-repair path=/bundle/migrations/002-repair",
            "run:/bundle/migrations/002-repair:",
        ])
    }

    func testRunFailsWhenMigrationIsNotExecutable() {
        let runner = RuntimeMigrationRunner(
            executableState: { _ in .present },
            runRequired: { _, _ in XCTFail("should not run invalid migration") },
            log: { _ in }
        )

        XCTAssertThrowsError(try runner.run([
            UpdateBundleMigration(name: "001-refresh", sha256: "abc", size: 10),
        ], stagedBundle: URL(fileURLWithPath: "/bundle"))) { error in
            XCTAssertEqual(
                String(describing: error),
                "migration is not executable: /bundle/migrations/001-refresh state=present"
            )
        }
    }

    func testRunFailsWhenMigrationInspectionFails() {
        let runner = RuntimeMigrationRunner(
            executableState: { _ in .inspectFailed("permission denied") },
            runRequired: { _, _ in XCTFail("should not run invalid migration") },
            log: { _ in }
        )

        XCTAssertThrowsError(try runner.run([
            UpdateBundleMigration(name: "001-refresh", sha256: "abc", size: 10),
        ], stagedBundle: URL(fileURLWithPath: "/bundle"))) { error in
            XCTAssertEqual(
                String(describing: error),
                "migration path inspection failed: /bundle/migrations/001-refresh reason=permission denied"
            )
        }
    }
}
