import Foundation
import Application
import RuntimeControl
import Errors

struct RuntimeLogArchivePruner {
    let archiveDirectory: URL
    let configuration: RuntimeLogArchiveRetentionConfiguration
    let fileStore: RuntimeFileStore
    let calendar: Calendar
    let now: () -> Date

    init(
        archiveDirectory: URL,
        configuration: RuntimeLogArchiveRetentionConfiguration,
        fileStore: RuntimeFileStore,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.archiveDirectory = archiveDirectory
        self.configuration = configuration
        self.fileStore = fileStore
        self.calendar = calendar
        self.now = now
    }

    func prune() throws {
        guard RuntimeLogArchiveRetentionPolicy.isValidRetentionDays(configuration.retentionDays) else {
            throw RuntimeControlLogCollectorError.invalidArchiveRetentionDays(configuration.retentionDays)
        }
        guard RuntimeLogArchiveRetentionPolicy.isValidMaximumBytes(configuration.maximumBytes) else {
            throw RuntimeControlLogCollectorError.invalidArchiveRetentionMaximumBytes(configuration.maximumBytes)
        }

        let archiveDirectoryState = fileStore.pathState(at: archiveDirectory)
        switch archiveDirectoryState {
        case .directory:
            break
        case .missing:
            return
        case .inspectFailed(let reason):
            throw RuntimeControlLogCollectorError.pathInspectionFailed(path: archiveDirectory.path, reason: reason)
        case .file, .other, .unknown:
            throw RuntimeControlLogCollectorError.unexpectedPathState(
                path: archiveDirectory.path,
                state: archiveDirectoryState.rawValue
            )
        }

        let entries: [URL]
        do {
            entries = try fileStore.contentsOfDirectory(at: archiveDirectory, skipsHiddenFiles: true)
        } catch {
            throw RuntimeControlLogCollectorError.directoryListingFailed(
                path: archiveDirectory.path,
                reason: String(describing: error)
            )
        }

        let archives = try entries.compactMap { entry -> RuntimeLogArchiveDay? in
            guard let day = Self.archiveDay(from: entry.lastPathComponent, calendar: calendar) else {
                return nil
            }
            let entryState = fileStore.pathState(at: entry)
            switch entryState {
            case .directory:
                break
            case .missing:
                return nil
            case .inspectFailed(let reason):
                throw RuntimeControlLogCollectorError.pathInspectionFailed(path: entry.path, reason: reason)
            case .file, .other, .unknown:
                throw RuntimeControlLogCollectorError.unexpectedPathState(
                    path: entry.path,
                    state: entryState.rawValue
                )
            }
            do {
                return RuntimeLogArchiveDay(
                    url: entry,
                    day: day,
                    sizeBytes: try fileStore.recursiveRegularFileSize(at: entry, skipsHiddenFiles: true)
                )
            } catch {
                throw RuntimeControlLogCollectorError.archiveSizeInspectionFailed(
                    path: entry.path,
                    reason: String(describing: error)
                )
            }
        }

        let candidates = RuntimeLogArchiveRetentionPolicy.pruneCandidates(
            archives: archives,
            configuration: configuration,
            now: now(),
            calendar: calendar
        )
        for candidate in candidates {
            do {
                try fileStore.removeItem(at: candidate)
            } catch {
                throw RuntimeControlLogCollectorError.archiveRemovalFailed(
                    path: candidate.path,
                    reason: String(describing: error)
                )
            }
        }
    }

    private static func archiveDay(from value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else {
            return nil
        }
        let normalized = calendar.dateComponents([.year, .month, .day], from: date)
        guard normalized.year == year,
              normalized.month == month,
              normalized.day == day
        else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }
}
