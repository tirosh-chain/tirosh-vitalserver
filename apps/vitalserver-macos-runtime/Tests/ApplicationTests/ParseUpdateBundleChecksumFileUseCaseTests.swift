import Application
import XCTest

final class ParseUpdateBundleChecksumFileUseCaseTests: XCTestCase {
    func testParseBuildsChecksumMapAndIgnoresMalformedLines() {
        let checksums = ParseUpdateBundleChecksumFileUseCase().parse(
            "abc123  rootfs-base.raw.gz\n"
                + "def456\tmigrations/001.sh\n"
                + "malformed\n"
                + "ghi789   artifacts/app.tar.gz   \n"
        )

        XCTAssertEqual(checksums, [
            "rootfs-base.raw.gz": "abc123",
            "migrations/001.sh": "def456",
            "artifacts/app.tar.gz": "ghi789",
        ])
    }
}
