import Domain
import Foundation
import Workflow
import XCTest

final class RuntimeBundleDigestVerifierTests: XCTestCase {
    func testVerifyReadsDigestAndSizeThenLogsCompletion() throws {
        let url = URL(fileURLWithPath: "/bundle/rootfs-base.raw.gz")
        let fileVerification = UpdateBundleFileVerification(
            name: "rootfs-base.raw.gz",
            checksumKey: "rootfs-base.raw.gz",
            expectedSHA256: "abc123",
            expectedSize: 1_024
        )
        var events: [String] = []
        let verifier = RuntimeBundleDigestVerifier(
            operations: RuntimeBundleDigestVerificationOperations(
                sha256: { fileURL in
                    events.append("sha256:\(fileURL.path)")
                    return "abc123"
                },
                fileSize: { fileURL in
                    events.append("size:\(fileURL.path)")
                    return 1_024
                },
                log: { message in
                    events.append("log:\(message)")
                }
            )
        )

        try verifier.verify(input: RuntimeBundleDigestVerificationInput(
            fileURL: url,
            fileVerification: fileVerification,
            checksumMap: ["rootfs-base.raw.gz": "abc123"]
        ))

        XCTAssertEqual(events, [
            "log:checksum started key=rootfs-base.raw.gz path=/bundle/rootfs-base.raw.gz expectedSize=0.0 MiB",
            "sha256:/bundle/rootfs-base.raw.gz",
            "size:/bundle/rootfs-base.raw.gz",
            "log:checksum completed key=rootfs-base.raw.gz actualSize=0.0 MiB",
        ])
    }

    func testVerifyReportsCoreDigestMismatchWithoutCompletionLog() {
        let url = URL(fileURLWithPath: "/bundle/rootfs-base.raw.gz")
        let fileVerification = UpdateBundleFileVerification(
            name: "rootfs-base.raw.gz",
            checksumKey: "rootfs-base.raw.gz",
            expectedSHA256: "expected",
            expectedSize: 10
        )
        var logs: [String] = []
        let verifier = RuntimeBundleDigestVerifier(
            operations: RuntimeBundleDigestVerificationOperations(
                sha256: { _ in "actual" },
                fileSize: { _ in 10 },
                log: { logs.append($0) }
            )
        )

        XCTAssertThrowsError(try verifier.verify(input: RuntimeBundleDigestVerificationInput(
            fileURL: url,
            fileVerification: fileVerification,
            checksumMap: ["rootfs-base.raw.gz": "actual"]
        ))) { error in
            XCTAssertEqual(error as? UpdateBundleVerificationError, .manifestChecksumMismatch("rootfs-base.raw.gz"))
        }
        XCTAssertEqual(logs.count, 1)
        XCTAssertTrue(logs[0].contains("checksum started"))
    }
}
