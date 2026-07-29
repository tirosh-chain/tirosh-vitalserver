import Application
import Contracts
import Foundation
import OutboundAdapters
import XCTest

final class UpdateBootstrapCompletionReportReaderTests: XCTestCase {
    func testReadsExplicitReportAndReturnsObservedDigest() {
        let root = URL(fileURLWithPath: "/updates/update-42")
        let reader = UpdateBootstrapCompletionReportReader(
            pathState: { _ in .file },
            readData: { _ in Data("report".utf8) },
            sha256: { _ in String(repeating: "a", count: 64) }
        )

        XCTAssertEqual(
            reader.readCompletionReport(
                relativePath: "handoff/report.json",
                beneath: root
            ),
            .loaded(
                path: "handoff/report.json",
                sha256: String(repeating: "a", count: 64)
            )
        )
    }

    func testPreservesMissingAndReadFailureSeparately() {
        let root = URL(fileURLWithPath: "/updates/update-42")
        let missing = UpdateBootstrapCompletionReportReader(
            pathState: { _ in .missing },
            readData: { _ in Data() },
            sha256: { _ in "" }
        )
        XCTAssertEqual(
            missing.readCompletionReport(
                relativePath: "handoff/report.json",
                beneath: root
            ),
            .missing(path: "handoff/report.json")
        )

        let failed = UpdateBootstrapCompletionReportReader(
            pathState: { _ in .file },
            readData: { _ in throw ReportReaderTestError.denied },
            sha256: { _ in "" }
        )
        XCTAssertEqual(
            failed.readCompletionReport(
                relativePath: "handoff/report.json",
                beneath: root
            ),
            .readFailed(
                path: "handoff/report.json",
                reason: "denied"
            )
        )
    }
}

private enum ReportReaderTestError: Error {
    case denied
}
