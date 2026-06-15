import Application
import Domain
import XCTest

final class ValidateUpdateBundleArchiveUseCaseTests: XCTestCase {
    func testRootDirectoryPreservesSingleRootPolicy() throws {
        let root = try ValidateUpdateBundleArchiveUseCase().rootDirectory(listOutput: """
        update-bundle/
        update-bundle/manifest.json
        """)

        XCTAssertEqual(root, "update-bundle")
    }

    func testRootDirectoryRejectsUnsafeArchivePath() {
        XCTAssertThrowsError(try ValidateUpdateBundleArchiveUseCase().rootDirectory(listOutput: "../escape\n")) { error in
            XCTAssertEqual(error as? UpdateBundleArchiveVerificationError, .unsafePath("../escape"))
        }
    }

    func testEntryTypeValidationRejectsLinksWithoutAdapterFallback() {
        XCTAssertThrowsError(try ValidateUpdateBundleArchiveUseCase().rejectUnsupportedEntryTypes(
            verboseListOutput: "lrwxr-xr-x 0 user group 0 Jan 1 00:00 update-bundle/link\n",
            archiveName: "update-bundle.tar.gz"
        )) { error in
            XCTAssertEqual(error as? UpdateBundleArchiveVerificationError, .containsLink("update-bundle.tar.gz"))
        }
    }

    func testArtifactArchiveEntryValidationRejectsUnexpectedRootWithoutAdapterPolicy() {
        XCTAssertThrowsError(try ValidateUpdateBundleArchiveUseCase().validateArtifactArchiveEntries(
            listOutput: "unexpected-tool\n",
            archiveName: "runtime-tools.tar.gz",
            allowedRootEntries: ["vitalserver-vm"]
        )) { error in
            XCTAssertEqual(
                error as? UpdateBundleArchiveVerificationError,
                .unexpectedRootEntry("runtime-tools.tar.gz", "unexpected-tool")
            )
        }
    }

    func testArtifactArchiveValidationFailureMessageMapsEntryTypePolicyErrors() {
        let useCase = ValidateUpdateBundleArchiveUseCase()

        XCTAssertEqual(
            useCase.artifactArchiveValidationFailureMessage(
                UpdateBundleArchiveVerificationError.emptyArchive,
                archiveName: "app-bundle.tar.gz"
            ),
            "empty tar.gz: app-bundle.tar.gz"
        )
        XCTAssertEqual(
            useCase.artifactArchiveValidationFailureMessage(
                UpdateBundleArchiveVerificationError.unsafePath("VitalServer Helper.app/../escape"),
                archiveName: "app-bundle.tar.gz"
            ),
            "path traversal in app-bundle.tar.gz: VitalServer Helper.app/../escape"
        )
        XCTAssertEqual(
            useCase.artifactArchiveValidationFailureMessage(
                UpdateBundleArchiveVerificationError.unexpectedTopLevelEntry("ignored.tar.gz", "Other.app"),
                archiveName: "app-bundle.tar.gz"
            ),
            "unexpected top-level entry in app-bundle.tar.gz: Other.app"
        )
        XCTAssertEqual(
            useCase.artifactArchiveValidationFailureMessage(
                UpdateBundleArchiveVerificationError.unexpectedRootEntry("ignored.tar.gz", "unexpected-tool"),
                archiveName: "runtime-tools.tar.gz"
            ),
            "unexpected root entry in runtime-tools.tar.gz: unexpected-tool"
        )
        XCTAssertEqual(
            useCase.artifactArchiveValidationFailureMessage(
                UpdateBundleArchiveVerificationError.containsLink("ignored.tar.gz"),
                archiveName: "app-bundle.tar.gz"
            ),
            "tar.gz must not contain links: app-bundle.tar.gz"
        )
        XCTAssertEqual(
            useCase.artifactArchiveValidationFailureMessage(
                UpdateBundleArchiveVerificationError.containsUnsupportedEntry("ignored.tar.gz", "c"),
                archiveName: "app-bundle.tar.gz"
            ),
            "tar.gz must contain only regular files and directories: app-bundle.tar.gz entryType=c"
        )
    }
}
