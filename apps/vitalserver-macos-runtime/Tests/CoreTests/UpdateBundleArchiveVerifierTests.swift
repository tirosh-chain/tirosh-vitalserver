import Core
import XCTest

final class UpdateBundleArchiveVerifierTests: XCTestCase {
    func testRootDirectoryReturnsSingleTopLevelDirectory() throws {
        let root = try UpdateBundleArchiveVerifier.rootDirectory(listOutput: """
        update-bundle/
        update-bundle/manifest.json
        update-bundle/artifacts/app.tar.gz
        """)

        XCTAssertEqual(root, "update-bundle")
    }

    func testRootDirectoryRejectsEmptyUnsafeAndMultipleRootArchives() {
        assertRootDirectoryError("", .emptyArchive)
        assertRootDirectoryError("/absolute/manifest.json", .unsafePath("/absolute/manifest.json"))
        assertRootDirectoryError("bundle\\manifest.json", .unsafePath("bundle\\manifest.json"))
        assertRootDirectoryError("bundle/../manifest.json", .unsafePath("bundle/../manifest.json"))
        assertRootDirectoryError("bundle/./manifest.json", .unsafePath("bundle/./manifest.json"))
        assertRootDirectoryError("""
        bundle-a/manifest.json
        bundle-b/manifest.json
        """, .multipleRootDirectories)
    }

    func testRejectUnsupportedEntryTypesFailsForSymlinkAndHardlinkEntries() {
        assertRejectUnsupportedEntryError(
            """
            drwxr-xr-x  0 root wheel 0 Jan 1 00:00 update-bundle/
            lrwxr-xr-x  0 root wheel 0 Jan 1 00:00 update-bundle/link
            """,
            .containsLink("update-bundle.tar.gz")
        )

        assertRejectUnsupportedEntryError(
            """
            hrwxr-xr-x  0 root wheel 0 Jan 1 00:00 update-bundle/hardlink
            """,
            .containsLink("update-bundle.tar.gz")
        )
    }

    func testRejectUnsupportedEntryTypesFailsForUnsupportedEntryTypes() {
        assertRejectUnsupportedEntryError(
            """
            crw-r--r--  0 root wheel 0 Jan 1 00:00 update-bundle/device
            """,
            .containsUnsupportedEntry("update-bundle.tar.gz", "c")
        )
    }

    func testRejectUnsupportedEntryTypesAllowsDirectoriesAndRegularFiles() throws {
        try UpdateBundleArchiveVerifier.rejectUnsupportedEntryTypes(
            verboseListOutput: """
            drwxr-xr-x  0 root wheel 0 Jan 1 00:00 update-bundle/
            -rw-r--r--  0 root wheel 0 Jan 1 00:00 update-bundle/manifest.json
            """,
            archiveName: "update-bundle.tar.gz"
        )
    }

    private func assertRootDirectoryError(
        _ output: String,
        _ expected: UpdateBundleArchiveVerificationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try UpdateBundleArchiveVerifier.rootDirectory(listOutput: output),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? UpdateBundleArchiveVerificationError, expected, file: file, line: line)
        }
    }

    private func assertRejectUnsupportedEntryError(
        _ output: String,
        _ expected: UpdateBundleArchiveVerificationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try UpdateBundleArchiveVerifier.rejectUnsupportedEntryTypes(
                verboseListOutput: output,
                archiveName: "update-bundle.tar.gz"
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? UpdateBundleArchiveVerificationError, expected, file: file, line: line)
        }
    }
}
