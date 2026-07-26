import Application
import Contracts
import Errors
import OutboundAdapters
import XCTest

final class RuntimePackageReceiptStateReaderTests: XCTestCase {
    private let identifier = "ai.tirosh.vitalserver.helper"

    func testCatalogMembershipAndStrictPlistReportVersionedReceiptPresent() {
        var commands: [[String]] = []

        let state = readState(
            catalog: success("\(identifier)\n"),
            info: success(packageInfoPlist(identifier: identifier, version: "0.2.1")),
            commands: &commands
        )

        XCTAssertEqual(
            state,
            .present(
                identifier: identifier,
                version: RuntimePackageVersion(rawValue: "0.2.1")!
            )
        )
        XCTAssertEqual(
            commands,
            [
                ["--pkgs"],
                ["--pkg-info-plist", identifier],
            ]
        )
    }

    func testSuccessfulCatalogWithoutExactIdentifierReportsAbsentWithoutReadingInfo() {
        var commands: [[String]] = []

        let state = readState(
            catalog: success("\(identifier).tools\nexample.other\n"),
            info: nil,
            commands: &commands
        )

        XCTAssertEqual(state, .absent(identifier: identifier))
        XCTAssertEqual(commands, [["--pkgs"]])
    }

    func testCatalogFailureContainingHumanNoReceiptTextReportsReadFailure() {
        let state = readState(
            catalog: RuntimeProcessResult(
                exitCode: 1,
                stdout: "",
                stderr: "No receipt for '\(identifier)' found at '/'.\n"
            )
        )

        guard case .readFailed(let actualIdentifier, let reason) = state else {
            return XCTFail("catalog command failure must remain readFailed")
        }
        XCTAssertEqual(actualIdentifier, identifier)
        XCTAssertTrue(reason.contains("pkgutil receipt catalog read failed"))
        XCTAssertTrue(reason.contains("No receipt"))
    }

    func testCatalogExecutionIssueReportsReadFailure() {
        let state = readState(
            catalog: RuntimeProcessResult(
                exitCode: 127,
                stdout: "",
                stderr: "",
                executionIssue: RuntimeProcessExecutionIssue(
                    kind: .processLaunchFailed,
                    message: "pkgutil denied"
                )
            )
        )

        guard case .readFailed(_, let reason) = state else {
            return XCTFail("catalog execution issue must remain readFailed")
        }
        XCTAssertTrue(reason.contains("pkgutil receipt catalog read failed"))
        XCTAssertTrue(reason.contains("processLaunchFailed: pkgutil denied"))
    }

    func testCatalogOutputIssueReportsReadFailure() {
        let state = readState(
            catalog: RuntimeProcessResult(
                exitCode: 0,
                stdout: "",
                stderr: "",
                outputIssues: [
                    RuntimeCommandOutputIssue(
                        stream: .stdout,
                        message: "pkgutil stdout is not valid UTF-8"
                    ),
                ]
            )
        )

        guard case .readFailed(_, let reason) = state else {
            return XCTFail("catalog output issue must remain readFailed")
        }
        XCTAssertTrue(reason.contains("pkgutil receipt catalog read failed"))
        XCTAssertTrue(reason.contains("stdout:pkgutil stdout is not valid UTF-8"))
    }

    func testDuplicateCatalogIdentifierReportsReadFailure() {
        let state = readState(
            catalog: success("\(identifier)\n\(identifier)\n")
        )

        XCTAssertEqual(
            state,
            .readFailed(
                identifier: identifier,
                reason: "pkgutil receipt catalog contains duplicate package-id value=\(identifier)"
            )
        )
    }

    func testPresentCatalogWithInfoCommandFailureReportsReadFailure() {
        let state = readState(
            catalog: success("\(identifier)\n"),
            info: RuntimeProcessResult(
                exitCode: 2,
                stdout: "",
                stderr: "receipt database locked"
            )
        )

        guard case .readFailed(_, let reason) = state else {
            return XCTFail("receipt info command failure must remain readFailed")
        }
        XCTAssertTrue(reason.contains("pkgutil receipt info read failed"))
        XCTAssertTrue(reason.contains("receipt database locked"))
    }

    func testPlistWithoutVersionReportsReadFailure() {
        let state = readState(
            catalog: success("\(identifier)\n"),
            info: success("""
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>pkgid</key>
              <string>\(identifier)</string>
            </dict>
            </plist>
            """)
        )

        guard case .readFailed(_, let reason) = state else {
            return XCTFail("missing version must remain readFailed")
        }
        XCTAssertTrue(reason.contains("pkgutil receipt plist decode failed"))
        XCTAssertTrue(reason.contains("pkg-version"))
    }

    func testPlistWithMalformedVersionReportsReadFailure() {
        let state = readState(
            catalog: success("\(identifier)\n"),
            info: success(packageInfoPlist(identifier: identifier, version: "0.2.1-dev"))
        )

        XCTAssertEqual(
            state,
            .readFailed(
                identifier: identifier,
                reason: "pkgutil receipt version is invalid value=0.2.1-dev"
            )
        )
    }

    func testPlistWithMismatchedPackageIdentifierReportsReadFailure() {
        let state = readState(
            catalog: success("\(identifier)\n"),
            info: success(packageInfoPlist(identifier: "example.other.package", version: "0.2.1"))
        )

        XCTAssertEqual(
            state,
            .readFailed(
                identifier: identifier,
                reason: "pkgutil receipt identifier mismatch actual=example.other.package expected=\(identifier)"
            )
        )
    }

    func testPlistWithDuplicatePackageIdentifierKeyReportsReadFailure() {
        let state = readState(
            catalog: success("\(identifier)\n"),
            info: success(packageInfoPlist(
                identifier: identifier,
                version: "0.2.1",
                additionalEntries: """
                  <key>pkgid</key>
                  <string>\(identifier)</string>
                """
            ))
        )

        XCTAssertEqual(
            state,
            .readFailed(
                identifier: identifier,
                reason: "pkgutil receipt plist contains duplicate key=pkgid"
            )
        )
    }

    func testPlistWithDuplicateVersionKeyReportsReadFailure() {
        let state = readState(
            catalog: success("\(identifier)\n"),
            info: success(packageInfoPlist(
                identifier: identifier,
                version: "0.2.1",
                additionalEntries: """
                  <key>
                    pkg-version
                  </key>
                  <string>0.2.1</string>
                """
            ))
        )

        XCTAssertEqual(
            state,
            .readFailed(
                identifier: identifier,
                reason: "pkgutil receipt plist contains duplicate key=pkg-version"
            )
        )
    }

    private func readState(
        catalog: RuntimeProcessResult,
        info: RuntimeProcessResult? = nil
    ) -> RuntimePackageReceiptState {
        var commands: [[String]] = []
        return readState(catalog: catalog, info: info, commands: &commands)
    }

    private func readState(
        catalog: RuntimeProcessResult,
        info: RuntimeProcessResult?,
        commands: inout [[String]]
    ) -> RuntimePackageReceiptState {
        RuntimePackageReceiptStateReader.state(
            identifier: identifier,
            runProcess: { executable, arguments in
                XCTAssertEqual(executable, "/usr/sbin/pkgutil")
                commands.append(arguments)
                switch arguments {
                case ["--pkgs"]:
                    return catalog
                case ["--pkg-info-plist", self.identifier]:
                    guard let info else {
                        XCTFail("receipt info must not be read for this observation")
                        return RuntimeProcessResult(
                            exitCode: 127,
                            stdout: "",
                            stderr: "unexpected receipt info read"
                        )
                    }
                    return info
                default:
                    XCTFail("unexpected pkgutil arguments: \(arguments)")
                    return RuntimeProcessResult(
                        exitCode: 127,
                        stdout: "",
                        stderr: "unexpected command"
                    )
                }
            }
        )
    }

    private func success(_ stdout: String) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    private func packageInfoPlist(
        identifier: String,
        version: String,
        additionalEntries: String = ""
    ) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>pkgid</key>
          <string>\(identifier)</string>
          <key>pkg-version</key>
          <string>\(version)</string>
        \(additionalEntries)
        </dict>
        </plist>
        """
    }
}
