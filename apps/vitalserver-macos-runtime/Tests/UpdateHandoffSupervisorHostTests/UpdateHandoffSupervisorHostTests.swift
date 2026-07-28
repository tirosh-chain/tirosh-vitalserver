import Contracts
import Foundation
@testable import UpdateHandoffSupervisorHost
import XCTest

final class UpdateHandoffSupervisorHostTests: XCTestCase {
    func testChildOwnerPublishesIdentityAndExplicitExitReceipt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let start = root.appendingPathComponent("start.json")
        let completion = root.appendingPathComponent("completion.json")

        try UpdateHandoffSupervisorHost().run(arguments: [
            "run-child",
            "--job-id", "job-1",
            "--launch-id", "launch-1",
            "--updater", "/usr/bin/true",
            "--invocation", "/tmp/invocation.json",
            "--start-receipt", start.path,
            "--completion-receipt", completion.path,
        ])

        let startReceipt = try JSONDecoder().decode(
            UpdateHandoffChildStartReceipt.self,
            from: Data(contentsOf: start)
        )
        let completionReceipt = try JSONDecoder().decode(
            UpdateHandoffChildCompletionReceipt.self,
            from: Data(contentsOf: completion)
        )
        XCTAssertEqual(startReceipt.jobId, "job-1")
        XCTAssertEqual(startReceipt.child.launchId, "launch-1")
        XCTAssertEqual(
            completionReceipt.processId,
            startReceipt.child.processId
        )
        XCTAssertEqual(completionReceipt.exitCode, 0)
        XCTAssertNil(completionReceipt.launchFailureReason)
    }
}
