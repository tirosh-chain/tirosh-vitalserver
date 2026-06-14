import XCTest
@testable import Contracts

final class RuntimeBackupSchedulePolicyTests: XCTestCase {
    func testValidatesStrictHHmmTimes() {
        XCTAssertTrue(RuntimeBackupSchedulePolicy.isValidTime("00:00"))
        XCTAssertTrue(RuntimeBackupSchedulePolicy.isValidTime("23:59"))

        XCTAssertFalse(RuntimeBackupSchedulePolicy.isValidTime("3:15"))
        XCTAssertFalse(RuntimeBackupSchedulePolicy.isValidTime("03:5"))
        XCTAssertFalse(RuntimeBackupSchedulePolicy.isValidTime("24:00"))
        XCTAssertFalse(RuntimeBackupSchedulePolicy.isValidTime("03:60"))
        XCTAssertFalse(RuntimeBackupSchedulePolicy.isValidTime("03:15 "))
    }

    func testBuildsScheduledSlotIdentifierOnlyForConfiguredMinute() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 14,
            hour: 3,
            minute: 15,
            second: 45
        )))

        XCTAssertEqual(
            RuntimeBackupSchedulePolicy.scheduledSlotIdentifier(
                now: date,
                scheduleTimes: ["03:15"],
                calendar: calendar
            ),
            "2026-06-14T03:15"
        )
        XCTAssertNil(RuntimeBackupSchedulePolicy.scheduledSlotIdentifier(
            now: date,
            scheduleTimes: ["03:16"],
            calendar: calendar
        ))
    }
}
