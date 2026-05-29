import Foundation

enum RuntimeVMShutdownLogProbe {
    private static let diskSafeMarkers = [
        "All filesystems, swaps, loop devices, MD devices and DM devices detached.",
        "All filesystems unmounted.",
    ]

    static func diskSafeShutdownReached(in data: Data, after logWatermark: UInt64) -> Bool {
        let offset = Int(min(logWatermark, UInt64(data.count)))
        let currentShutdownLog = String(decoding: data.dropFirst(offset), as: UTF8.self)
        return diskSafeMarkers.contains { currentShutdownLog.contains($0) }
    }
}
