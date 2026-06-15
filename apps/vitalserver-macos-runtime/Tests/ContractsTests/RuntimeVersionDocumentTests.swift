import Contracts
import XCTest
import Errors

final class RuntimeVersionDocumentTests: XCTestCase {
    func testRuntimeVersionDocumentRoundTripsAppliedVersion() throws {
        let document = RuntimeVersionDocument(
            product: "ai.tirosh.vitalserver.helper",
            runtimeVersion: "1.2.3",
            appliedAt: "2026-06-05T00:00:00Z",
            bundle: "update-bundle-1.2.3",
            rootfsBase: "rootfs-base.raw.gz",
            vmDisk: "vm-disk.img"
        )

        let decoded = try JSONDecoder().decode(
            RuntimeVersionDocument.self,
            from: JSONEncoder().encode(document)
        )

        XCTAssertEqual(decoded, document)
    }

    func testInstalledRuntimeVersionDocumentRoundTripsInstalledVersion() throws {
        let document = InstalledRuntimeVersionDocument(
            product: "ai.tirosh.vitalserver.helper",
            runtimeVersion: "1.2.3",
            installedAt: "2026-06-05T00:00:00Z",
            rootfsBase: "rootfs-base.raw.gz",
            vmDisk: "vm-disk.img"
        )

        let decoded = try JSONDecoder().decode(
            InstalledRuntimeVersionDocument.self,
            from: JSONEncoder().encode(document)
        )

        XCTAssertEqual(decoded, document)
    }
}
