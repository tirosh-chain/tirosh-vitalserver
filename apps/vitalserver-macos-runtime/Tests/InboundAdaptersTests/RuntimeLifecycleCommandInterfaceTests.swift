import Foundation
import Application
import InboundAdapters
import XCTest
import Errors

final class RuntimeLifecycleCommandInterfaceTests: XCTestCase {
    func testParsesRuntimeArgumentsIntoTypedInterfaceCommand() throws {
        let command = try RuntimeLifecycleCommand.parseArguments([
            "configure",
            "--cpu",
            "8",
            "--network",
            "bridged",
            "--restart",
        ])

        XCTAssertEqual(command, .configure(RuntimeConfigureCommand(
            changes: [
                .cpu(8),
                .network(.bridged),
            ],
            restart: true
        )))
    }

    func testReportsTypedParseErrorsWithoutCLIHostErrorDependency() {
        XCTAssertThrowsError(try RuntimeLifecycleCommand.parseArguments(["configure", "--cpu"])) { error in
            XCTAssertEqual(
                error as? RuntimeLifecycleCommandParseError,
                .missingArgument("missing value for --cpu")
            )
        }

        XCTAssertThrowsError(try RuntimeLifecycleCommand.parseArguments(["unknown"])) { error in
            XCTAssertEqual(
                error as? RuntimeLifecycleCommandParseError,
                .unsupportedCommand("runtime unknown")
            )
        }
    }

    func testUsageTextListsRuntimeCommandsAtInterfaceBoundary() {
        XCTAssertTrue(RuntimeLifecycleCommand.usageText.contains("vitalserver-vm runtime install"))
        XCTAssertTrue(RuntimeLifecycleCommand.usageText.contains("vitalserver-vm runtime configure"))
        XCTAssertTrue(RuntimeLifecycleCommand.usageText.contains("vitalserver-vm runtime uninstall [--clean]"))
    }
}
