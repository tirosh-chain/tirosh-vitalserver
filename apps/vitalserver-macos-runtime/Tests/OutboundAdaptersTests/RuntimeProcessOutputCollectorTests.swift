import Contracts
import Foundation
import OutboundAdapters
import XCTest

final class RuntimeProcessOutputCollectorTests: XCTestCase {
  func testDrainsStdoutAndStderrLargerThanPipeBufferWithoutHang() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("collector-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    // Emit more than the default pipe buffer (16-64 KiB) to both streams.
    let script = root.appendingPathComponent("emit.sh")
    try Data(
      """
      #!/bin/sh
      yes a | head -c 262144
      yes b | head -c 262144 >&2
      """.utf8
    ).write(to: script)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: script.path
    )

    let outcome = RuntimeProcessOutputCollector().run(
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      arguments: [script.path]
    )

    XCTAssertEqual(outcome.exitCode, 0)
    XCTAssertNil(outcome.executionIssue)
    XCTAssertEqual(outcome.stdout.count, 262144)
    XCTAssertEqual(outcome.stderr.count, 262144)
    XCTAssertTrue(outcome.stdout.allSatisfy { $0 == "a" || $0 == "\n" })
    XCTAssertTrue(outcome.stderr.allSatisfy { $0 == "b" || $0 == "\n" })
  }

  func testLaunchFailureIsReportedWithoutHiding() throws {
    let outcome = RuntimeProcessOutputCollector().run(
      executableURL: URL(fileURLWithPath: "/nonexistent/executable"),
      arguments: []
    )
    XCTAssertNotNil(outcome.executionIssue)
    XCTAssertEqual(outcome.exitCode, 1)
  }

  func testFailedRunClearsDrainHandlersWithoutLeakingDescriptors() throws {
    let collector = RuntimeProcessOutputCollector()
    let before = openFileDescriptorCount()
    for _ in 0..<50 {
      let outcome = collector.run(
        executableURL: URL(fileURLWithPath: "/nonexistent/executable"),
        arguments: []
      )
      XCTAssertNotNil(outcome.executionIssue)
    }
    let after = openFileDescriptorCount()
    XCTAssertLessThanOrEqual(
      after,
      before + 4,
      "failed runs must clear readability handlers and close pipe FDs"
    )

    for _ in 0..<50 {
      let healthy = collector.run(
        executableURL: URL(fileURLWithPath: "/usr/bin/true"),
        arguments: []
      )
      XCTAssertNil(healthy.executionIssue)
      XCTAssertEqual(healthy.exitCode, 0)
    }
    let afterHealthyRuns = openFileDescriptorCount()
    XCTAssertLessThanOrEqual(
      afterHealthyRuns,
      after + 4,
      "successful runs must clear readability handlers and close pipe FDs"
    )
  }

  private func openFileDescriptorCount() -> Int {
    (try? FileManager.default.contentsOfDirectory(
      atPath: "/dev/fd"
    ))?.count ?? 0
  }
}
