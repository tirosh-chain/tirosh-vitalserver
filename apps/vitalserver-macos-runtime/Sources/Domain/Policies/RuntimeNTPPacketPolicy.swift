import Foundation

public enum RuntimeNTPPacketPolicy {
    public static let packetLength = 48
    public static let helperClockStratum: UInt8 = 10

    private static let ntpEpochOffset: TimeInterval = 2_208_988_800

    public static func response(
        to request: [UInt8],
        receivedAt: Date,
        transmittedAt: Date,
        referenceAt: Date
    ) -> [UInt8]? {
        guard request.count >= packetLength else {
            return nil
        }
        let version = (request[0] >> 3) & 0b111
        let mode = request[0] & 0b111
        guard (version == 3 || version == 4), mode == 3 else {
            return nil
        }

        var response = [UInt8](repeating: 0, count: packetLength)
        response[0] = (version << 3) | 4
        response[1] = helperClockStratum
        response[2] = request[2]
        response[3] = UInt8(bitPattern: -20)
        writeNTPShort(0.001, to: &response, offset: 8)
        response.replaceSubrange(12..<16, with: Array("LOCL".utf8))
        writeTimestamp(referenceAt, to: &response, offset: 16)
        response.replaceSubrange(24..<32, with: request[40..<48])
        writeTimestamp(receivedAt, to: &response, offset: 32)
        writeTimestamp(transmittedAt, to: &response, offset: 40)
        return response
    }

    public static func timestampBytes(for date: Date) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 8)
        writeTimestamp(date, to: &bytes, offset: 0)
        return bytes
    }

    private static func writeTimestamp(
        _ date: Date,
        to bytes: inout [UInt8],
        offset: Int
    ) {
        let ntpTime = date.timeIntervalSince1970 + ntpEpochOffset
        let seconds = UInt32(ntpTime.rounded(.down))
        let fraction = UInt32(
            ((ntpTime - ntpTime.rounded(.down)) * 4_294_967_296)
                .rounded(.down)
        )
        writeUInt32(seconds, to: &bytes, offset: offset)
        writeUInt32(fraction, to: &bytes, offset: offset + 4)
    }

    private static func writeNTPShort(
        _ seconds: Double,
        to bytes: inout [UInt8],
        offset: Int
    ) {
        let fixedPoint = UInt32((seconds * 65_536).rounded())
        writeUInt32(fixedPoint, to: &bytes, offset: offset)
    }

    private static func writeUInt32(
        _ value: UInt32,
        to bytes: inout [UInt8],
        offset: Int
    ) {
        bytes[offset] = UInt8((value >> 24) & 0xff)
        bytes[offset + 1] = UInt8((value >> 16) & 0xff)
        bytes[offset + 2] = UInt8((value >> 8) & 0xff)
        bytes[offset + 3] = UInt8(value & 0xff)
    }
}
