import XCTest
@testable import Domain

final class RuntimeNTPPacketPolicyTests: XCTestCase {
    func testBuildsServerResponseWithExplicitHelperClockEvidence() throws {
        var request = [UInt8](repeating: 0, count: 48)
        request[0] = (4 << 3) | 3
        request[2] = 6
        let clientTransmit = Array(UInt8(0x10)...UInt8(0x17))
        request.replaceSubrange(40..<48, with: clientTransmit)
        let receivedAt = Date(timeIntervalSince1970: 1_785_222_400.25)
        let transmittedAt = Date(timeIntervalSince1970: 1_785_222_400.5)
        let referenceAt = Date(timeIntervalSince1970: 1_785_222_399)

        let response = try XCTUnwrap(RuntimeNTPPacketPolicy.response(
            to: request,
            receivedAt: receivedAt,
            transmittedAt: transmittedAt,
            referenceAt: referenceAt
        ))

        XCTAssertEqual(response.count, 48)
        XCTAssertEqual(response[0] & 0b111, 4)
        XCTAssertEqual((response[0] >> 3) & 0b111, 4)
        XCTAssertEqual(response[1], RuntimeNTPPacketPolicy.helperClockStratum)
        XCTAssertEqual(response[2], 6)
        XCTAssertEqual(Array(response[12..<16]), Array("LOCL".utf8))
        XCTAssertEqual(Array(response[24..<32]), clientTransmit)
        XCTAssertEqual(
            Array(response[32..<40]),
            RuntimeNTPPacketPolicy.timestampBytes(for: receivedAt)
        )
        XCTAssertEqual(
            Array(response[40..<48]),
            RuntimeNTPPacketPolicy.timestampBytes(for: transmittedAt)
        )
    }

    func testRejectsShortNonClientAndUnsupportedVersionPackets() {
        XCTAssertNil(RuntimeNTPPacketPolicy.response(
            to: [UInt8](repeating: 0, count: 47),
            receivedAt: Date(),
            transmittedAt: Date(),
            referenceAt: Date()
        ))

        var serverPacket = [UInt8](repeating: 0, count: 48)
        serverPacket[0] = (4 << 3) | 4
        XCTAssertNil(RuntimeNTPPacketPolicy.response(
            to: serverPacket,
            receivedAt: Date(),
            transmittedAt: Date(),
            referenceAt: Date()
        ))

        var unsupportedVersion = [UInt8](repeating: 0, count: 48)
        unsupportedVersion[0] = (2 << 3) | 3
        XCTAssertNil(RuntimeNTPPacketPolicy.response(
            to: unsupportedVersion,
            receivedAt: Date(),
            transmittedAt: Date(),
            referenceAt: Date()
        ))
    }
}
