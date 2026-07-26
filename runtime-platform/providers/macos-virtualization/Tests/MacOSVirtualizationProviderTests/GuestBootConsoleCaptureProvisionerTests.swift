import Foundation
import Testing
@testable import MacOSVirtualizationProvider

private func guestBootConsoleCaptureFixture() throws -> (directory: URL, capture: GuestBootConsoleCapture) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("vitalserver-guest-boot-console-capture-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (
        directory,
        GuestBootConsoleCapture(
            capturePath: directory.appendingPathComponent("host-diagnostics/guest-boot-console.log").path,
            writeMode: "append"
        )
    )
}

@Test("C32 Host boot console provisioner creates an append-only capture and preserves existing evidence")
func guestBootConsoleCaptureProvisionerCreatesAndRetainsDeclaredCapture() throws {
    let fixture = try guestBootConsoleCaptureFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    #expect(try GuestBootConsoleCaptureProvisioner.provision(capture: fixture.capture) == .created)
    let captureURL = URL(fileURLWithPath: fixture.capture.capturePath)
    try Data("Guest serial evidence\n".utf8).write(to: captureURL)

    #expect(
        try GuestBootConsoleCaptureProvisioner.provision(capture: fixture.capture)
            == .retainedExistingAppendOnlyCapture
    )
    #expect(try Data(contentsOf: captureURL) == Data("Guest serial evidence\n".utf8))
}

@Test("C32 Host boot console provisioner rejects a directory presented as a capture file")
func guestBootConsoleCaptureProvisionerRejectsNonRegularCapture() throws {
    let fixture = try guestBootConsoleCaptureFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let captureURL = URL(fileURLWithPath: fixture.capture.capturePath)
    try FileManager.default.createDirectory(at: captureURL, withIntermediateDirectories: true)

    do {
        _ = try GuestBootConsoleCaptureProvisioner.provision(capture: fixture.capture)
        Issue.record("expected a non-regular boot console capture to be rejected")
    } catch let error as GuestBootConsoleCaptureProvisioningError {
        #expect(error.localizedDescription.contains("must be a regular file"))
    }
}
