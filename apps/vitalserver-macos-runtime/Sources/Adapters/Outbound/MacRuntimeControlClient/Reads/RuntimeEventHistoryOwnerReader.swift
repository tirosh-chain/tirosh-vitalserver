import Application
import Foundation

struct RuntimeEventHistoryOwnerReader {
    static func live(
        paths: RuntimeObservabilityPaths,
        fileStore: RuntimeFileStore
    ) -> any RuntimeEventHistoryReading {
        CompositeRuntimeEventRepository(
            primary: JSONLRuntimeEventRepository(
                url: URL(fileURLWithPath: paths.runtimeEvents),
                fileStore: fileStore
            ),
            secondary: SQLiteRuntimeEventRepository(
                url: URL(fileURLWithPath: paths.runtimeObservabilityDB)
            )
        )
    }
}
