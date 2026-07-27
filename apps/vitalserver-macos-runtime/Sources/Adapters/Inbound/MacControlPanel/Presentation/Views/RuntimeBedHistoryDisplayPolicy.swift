import Contracts
import Foundation
import RuntimeControl

struct RuntimeBedHistoryDisplayPolicy {
    enum BedSortOption: String, CaseIterable, Identifiable, Equatable, Sendable {
        case name
        case bedID
        case recorder
        case lastSeen
        case status

        var id: String { rawValue }

        var title: String {
            switch self {
            case .name:
                return "Name"
            case .bedID:
                return "Bed ID"
            case .recorder:
                return "VRecorder"
            case .lastSeen:
                return "Last seen"
            case .status:
                return "Status"
            }
        }
    }

    enum ReadPresentation: Equatable {
        case loaded
        case partiallyLoaded(String)
        case readFailed(String)
    }

    func readPresentation(
        _ history: RuntimeVitalBedHistory
    ) -> ReadPresentation {
        switch history.state {
        case .loaded:
            return .loaded
        case .partiallyLoaded:
            return .partiallyLoaded(
                history.readError ?? "No failure detail was provided."
            )
        case .readFailed:
            return .readFailed(
                history.readError ?? "No failure detail was provided."
            )
        }
    }

    func summaryText(
        _ value: Int,
        history: RuntimeVitalBedHistory
    ) -> String {
        history.state == .readFailed ? "Unavailable" : "\(value)"
    }

    func relationshipEventPageText(
        _ history: RuntimeVitalRelationshipHistory
    ) -> String {
        guard history.state != .readFailed else {
            return "Unavailable"
        }
        return "\(history.events.count) of \(history.eventTotalCount)"
    }

    func sortedBeds(
        _ beds: [RuntimeVitalBedRecord],
        by option: BedSortOption
    ) -> [RuntimeVitalBedRecord] {
        beds.sorted { lhs, rhs in
            switch option {
            case .name:
                return compareText(
                    lhs.name,
                    rhs.name,
                    tieBreaker: lhs.bedID < rhs.bedID
                )
            case .bedID:
                return compareText(
                    lhs.bedID,
                    rhs.bedID,
                    tieBreaker: lhs.bedID < rhs.bedID
                )
            case .recorder:
                return compareText(
                    lhs.vrcode,
                    rhs.vrcode,
                    tieBreaker: lhs.bedID < rhs.bedID
                )
            case .lastSeen:
                switch compareReportedTimestamp(lhs.lastSeenAt, rhs.lastSeenAt) {
                case .orderedDescending:
                    return true
                case .orderedAscending:
                    return false
                case .orderedSame:
                    return lhs.bedID < rhs.bedID
                }
            case .status:
                let lhsRank = statusRank(lhs.status)
                let rhsRank = statusRank(rhs.status)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.bedID < rhs.bedID
            }
        }
    }

    private func compareText(
        _ lhs: String?,
        _ rhs: String?,
        tieBreaker: Bool
    ) -> Bool {
        let lhsText = normalizedSortText(lhs)
        let rhsText = normalizedSortText(rhs)
        switch (lhsText, rhsText) {
        case let (lhsText?, rhsText?) where lhsText != rhsText:
            return lhsText < rhsText
        case (.some, .some):
            return tieBreaker
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return tieBreaker
        }
    }

    private func normalizedSortText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private func compareReportedTimestamp(
        _ lhs: String?,
        _ rhs: String?
    ) -> ComparisonResult {
        let lhsDate = reportedTimestampDate(lhs)
        let rhsDate = reportedTimestampDate(rhs)
        if let lhsDate, let rhsDate {
            if lhsDate == rhsDate {
                return .orderedSame
            }
            return lhsDate > rhsDate ? .orderedDescending : .orderedAscending
        }
        if lhsDate != nil {
            return .orderedDescending
        }
        if rhsDate != nil {
            return .orderedAscending
        }
        return .orderedSame
    }

    private func reportedTimestampDate(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private func statusRank(_ status: RuntimeVitalBedStatus) -> Int {
        switch status {
        case .online:
            return 0
        case .stale:
            return 1
        case .offline:
            return 2
        case .notObserved:
            return 3
        case .unknown:
            return 4
        }
    }
}
