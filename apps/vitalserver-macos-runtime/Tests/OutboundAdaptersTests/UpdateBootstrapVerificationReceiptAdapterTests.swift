import Application
import Contracts
import Darwin
import Domain
import Foundation
import OutboundAdapters
import XCTest

final class UpdateBootstrapVerificationReceiptAdapterTests: XCTestCase {
    func testWriterReplacesSameUpdateIdAtomically() throws {
        var events: [String] = []
        var stored: Data?
        let writer = UpdateBootstrapVerificationReceiptWriter(
            operations: UpdateBootstrapVerificationReceiptWriteOperations(
                pathState: { _ in .file },
                createDirectory: { url, intermediate in
                    events.append("create:\(url.path):\(intermediate)")
                },
                writeData: { data, url, options in
                    events.append(
                        "write:\(url.path):\(options.contains(.atomic))"
                    )
                    stored = data
                },
                validate: UpdateBootstrapVerificationReceiptPolicy.validate
            )
        )

        try writer.write(receipt(), to: destination)

        XCTAssertEqual(events, [
            "create:/Library/Application Support/VitalServerHelper/update-bootstrap-verification:true",
            "write:\(destination.path):true",
        ])
        let decoded = try JSONDecoder().decode(
            UpdateBootstrapVerificationReceipt.self,
            from: XCTUnwrap(stored)
        )
        XCTAssertEqual(decoded, receipt())
    }

    func testWriterRejectsPathBoundToADifferentUpdateId() {
        var wrote = false
        let writer = UpdateBootstrapVerificationReceiptWriter(
            operations: UpdateBootstrapVerificationReceiptWriteOperations(
                pathState: { _ in .missing },
                createDirectory: { _, _ in },
                writeData: { _, _, _ in wrote = true },
                validate: UpdateBootstrapVerificationReceiptPolicy.validate
            )
        )

        XCTAssertThrowsError(
            try writer.write(
                receipt(),
                to: URL(
                    fileURLWithPath:
                        "/Library/Application Support/VitalServerHelper/update-bootstrap-verification/update-99.json"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapVerificationReceiptWriteError,
                .destinationIdentityMismatch(
                    expected: "update-42.json",
                    actual: "update-99.json"
                )
            )
        }
        XCTAssertFalse(wrote)
    }

    func testWriterDoesNotTreatDirectoryAsReplaceableReceipt() {
        var wrote = false
        let writer = UpdateBootstrapVerificationReceiptWriter(
            operations: UpdateBootstrapVerificationReceiptWriteOperations(
                pathState: { _ in .directory },
                createDirectory: { _, _ in },
                writeData: { _, _, _ in wrote = true },
                validate: UpdateBootstrapVerificationReceiptPolicy.validate
            )
        )

        XCTAssertThrowsError(try writer.write(receipt(), to: destination)) {
            error in
            XCTAssertEqual(
                error as? UpdateBootstrapVerificationReceiptWriteError,
                .destinationIsDirectory(path: destination.path)
            )
        }
        XCTAssertFalse(wrote)
    }

    func testWriterMapsPermissionDeniedWithoutCallingItMissing() {
        let writer = UpdateBootstrapVerificationReceiptWriter(
            operations: UpdateBootstrapVerificationReceiptWriteOperations(
                pathState: { _ in .missing },
                createDirectory: { _, _ in },
                writeData: { _, _, _ in
                    throw NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(EACCES),
                        userInfo: nil
                    )
                },
                validate: UpdateBootstrapVerificationReceiptPolicy.validate
            )
        )

        XCTAssertThrowsError(try writer.write(receipt(), to: destination)) {
            error in
            guard case .writePermissionDenied(let path, let reason)? =
                error as? UpdateBootstrapVerificationReceiptWriteError else {
                return XCTFail("expected write permission denied")
            }
            XCTAssertEqual(path, destination.path)
            XCTAssertTrue(reason.contains("13") || reason.contains("Permission"))
        }
    }

    func testReaderKeepsMissingDistinctFromDecodeFailure() {
        let reader = UpdateBootstrapVerificationReceiptReader(
            pathState: { _ in .missing },
            readData: { _ in
                XCTFail("must not read missing receipt")
                return Data()
            }
        )

        XCTAssertEqual(
            reader.read(at: destination),
            .missing(path: destination.path)
        )
    }

    func testReaderKeepsPermissionDeniedDistinctFromReadFailure() {
        let denied = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EACCES),
            userInfo: nil
        )
        let reader = UpdateBootstrapVerificationReceiptReader(
            pathState: { _ in .file },
            readData: { _ in throw denied }
        )

        XCTAssertEqual(
            reader.read(at: destination),
            .permissionDenied(
                path: destination.path,
                reason: String(describing: denied)
            )
        )
    }

    func testReaderKeepsUnknownFieldAsDecodeFailure() throws {
        var document = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(receipt())
        ) as! [String: Any]
        document["legacyHome"] = "/var/root/.tirosh"
        let data = try JSONSerialization.data(withJSONObject: document)
        let reader = UpdateBootstrapVerificationReceiptReader(
            pathState: { _ in .file },
            readData: { _ in data }
        )

        guard case .decodeFailed(let path, let reason) =
            reader.read(at: destination) else {
            return XCTFail("expected decode failure")
        }
        XCTAssertEqual(path, destination.path)
        XCTAssertTrue(reason.contains("unsupported fields"))
    }

    func testProcessIdentityReaderReportsExplicitUidAndEuid() {
        let identity = SystemProcessUserIdentityReader().read()

        XCTAssertEqual(identity.uid, getuid())
        XCTAssertEqual(identity.euid, geteuid())
    }

    private var destination: URL {
        URL(
            fileURLWithPath:
                "/Library/Application Support/VitalServerHelper/update-bootstrap-verification/update-42.json"
        )
    }

    private func receipt() -> UpdateBootstrapVerificationReceipt {
        UpdateBootstrapVerificationReceipt(
            schemaVersion: UpdateBootstrapVerificationReceiptContract
                .schemaVersion,
            command: UpdateBootstrapVerificationReceiptContract.command,
            updateId: "update-42",
            canonicalPayloadSHA256: String(repeating: "ab", count: 32),
            resolvedRuntimeHome:
                "/Library/Application Support/VitalServerHelper/vm",
            trustStorePath:
                "/Library/Application Support/VitalServerHelper/config/update-bootstrap-trust-store.json",
            observedAt: "2026-08-24T00:00:00Z",
            uid: 0,
            euid: 0
        )
    }
}
