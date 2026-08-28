import Application
import Contracts
import Domain
import Foundation
@testable import OutboundAdapters
import XCTest

final class SQLiteInstalledProductReleaseReaderTests: XCTestCase {
    func testReadsValidatedPackageInstallRelease() throws {
        let context = try makeContext()
        let release = try InstalledProductReleasePolicy.makePackageInstall(
            installationId: "installation-1",
            productId: "ai.tirosh.vitalserver.helper",
            productVersion: "0.2.2",
            runtimeVersion: "0.2.2",
            installOperationId: "install-1",
            settledAt: "2026-07-27T00:00:00Z"
        )
        try context.writer.settlePackageInstallRelease(release)

        XCTAssertEqual(
            context.reader.loadInstalledProductRelease(),
            .loaded(release)
        )
    }

    func testReportsMissingReleaseDistinctly() throws {
        let context = try makeContext()

        XCTAssertEqual(
            context.reader.loadInstalledProductRelease(),
            .missing
        )
    }

    func testReportsColumnAndDocumentIdentityMismatchAsFailure() throws {
        let context = try makeContext()
        let release = try InstalledProductReleasePolicy.makePackageInstall(
            installationId: "installation-1",
            productId: "ai.tirosh.vitalserver.helper",
            productVersion: "0.2.2",
            runtimeVersion: "0.2.2",
            installOperationId: "install-1",
            settledAt: "2026-07-27T00:00:00Z"
        )
        try context.writer.settlePackageInstallRelease(release)
        let connection = SQLiteHostRuntimeStateConnection(
            url: context.databaseURL,
            busyTimeoutMilliseconds: 5_000
        )
        try connection.withWritableDatabase { db in
            try SQLiteHostRuntimeStateStatement.execute(
                db,
                sql: """
                UPDATE installed_product_release
                SET installation_id = 'installation-corrupt'
                WHERE singleton_id = 1
                """
            )
        }

        guard case .failed(let reason) =
            context.reader.loadInstalledProductRelease() else {
            return XCTFail("expected explicit read failure")
        }
        XCTAssertTrue(
            reason.contains(
                "installed_product_release.installation_id"
            )
        )
    }

    private func makeContext() throws -> (
        reader: SQLiteInstalledProductReleaseReader,
        writer: SQLiteUpdateBootstrapJournalRepository,
        databaseURL: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        _ = try SQLiteHostRuntimeStateDatabase(url: databaseURL).initialize()
        return (
            SQLiteInstalledProductReleaseReader(
                databaseURL: databaseURL,
                validate: ValidateInstalledProductReleaseUseCase().validate
            ),
            SQLiteUpdateBootstrapJournalRepository(
                databaseURL: databaseURL,
                validate: ValidateUpdateBootstrapJournalUseCase().validate,
                validateRelease: InstalledProductReleasePolicy.validate,
                validateSettlement: InstalledProductReleasePolicy.validate
            ),
            databaseURL
        )
    }
}

final class RuntimeHostInstalledProductReleaseVersionReaderTests: XCTestCase {
    func testMapsLoadedReleaseToRuntimeVersion() throws {
        let release = try InstalledProductReleasePolicy.makePackageInstall(
            installationId: "installation-1",
            productId: "ai.tirosh.vitalserver.helper",
            productVersion: "0.2.2",
            runtimeVersion: "runtime-2026.07",
            installOperationId: "install-1",
            settledAt: "2026-07-27T00:00:00Z"
        )
        let read = RuntimeHostInstalledProductReleaseVersionReader(
            reader: StubInstalledProductReleaseReader(result: .loaded(release))
        ).loadRuntimeVersionRead()

        XCTAssertEqual(read.version, "runtime-2026.07")
        XCTAssertNil(read.issue)
    }

    func testPreservesMissingReleaseAsReadIssue() {
        let read = RuntimeHostInstalledProductReleaseVersionReader(
            reader: StubInstalledProductReleaseReader(result: .missing)
        ).loadRuntimeVersionRead()

        XCTAssertNil(read.version)
        XCTAssertEqual(read.issue?.source, "installedProductRelease")
        XCTAssertEqual(read.issue?.message, "installed product release is missing")
    }

    func testPreservesRepositoryFailureAsReadIssue() {
        let read = RuntimeHostInstalledProductReleaseVersionReader(
            reader: StubInstalledProductReleaseReader(
                result: .failed(reason: "database permission denied")
            )
        ).loadRuntimeVersionRead()

        XCTAssertNil(read.version)
        XCTAssertEqual(read.issue?.source, "installedProductRelease")
        XCTAssertEqual(read.issue?.message, "database permission denied")
    }
}

private struct StubInstalledProductReleaseReader: InstalledProductReleaseReading {
    let result: InstalledProductReleaseReadResult

    func loadInstalledProductRelease() -> InstalledProductReleaseReadResult {
        result
    }
}
