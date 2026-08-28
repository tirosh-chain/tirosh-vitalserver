import Application
import Contracts
import Foundation
import OutboundAdapters
import XCTest

final class UpdateBootstrapCompletionReceiptReaderTests: XCTestCase {
    func testMissingReceiptRemainsMissing() {
        let reader = UpdateBootstrapCompletionReceiptReader(
            pathState: { _ in .missing },
            readData: { _ in XCTFail("must not read missing receipt"); return Data() }
        )

        XCTAssertEqual(
            reader.readCompletionReceipt(at: receiptURL),
            .missing(path: receiptURL.path)
        )
    }

    func testUnknownFieldIsDecodeFailure() throws {
        var document = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(receipt())
        ) as! [String: Any]
        document["legacySuccess"] = true
        let data = try JSONSerialization.data(withJSONObject: document)
        let reader = UpdateBootstrapCompletionReceiptReader(
            pathState: { _ in .file },
            readData: { _ in data }
        )

        guard case .decodeFailed(let path, let reason) =
                reader.readCompletionReceipt(at: receiptURL) else {
            return XCTFail("expected decode failure")
        }
        XCTAssertEqual(path, receiptURL.path)
        XCTAssertTrue(reason.contains("unsupported fields"))
    }

    func testLoadsStrictReceiptWithoutSettlingJournal() throws {
        let expected = receipt()
        let reader = UpdateBootstrapCompletionReceiptReader(
            pathState: { _ in .file },
            readData: { _ in try JSONEncoder().encode(expected) }
        )

        XCTAssertEqual(
            reader.readCompletionReceipt(at: receiptURL),
            .loaded(expected)
        )
    }

    private var receiptURL: URL {
        URL(
            fileURLWithPath:
                "/updates/update-42/handoff/completion-receipt.json"
        )
    }

    private func receipt() -> UpdateBootstrapCompletionReceipt {
        UpdateBootstrapCompletionReceipt(
            schemaVersion: "v1",
            updateId: "update-42",
            requestId: "request-42",
            bootstrapEnvelopeId: "envelope-42",
            updateSpecificationSHA256: String(repeating: "b", count: 64),
            expectedJournalRevision: 3,
            outcome: .succeeded,
            reportRelativePath: "handoff/report.json",
            reportSHA256: String(repeating: "c", count: 64),
            failureReason: nil,
            finishedAt: "2026-07-27T06:10:00Z"
        )
    }
}
