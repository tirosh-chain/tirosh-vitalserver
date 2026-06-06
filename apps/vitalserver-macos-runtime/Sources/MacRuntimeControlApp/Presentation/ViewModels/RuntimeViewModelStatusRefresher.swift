import Interfaces

typealias RuntimeViewModelStatusSnapshotLoading = Interfaces.RuntimeViewModelStatusSnapshotLoading
typealias RuntimeViewModelStatusPresentationFormatting = Interfaces.RuntimeViewModelStatusPresentationFormatting
typealias RuntimeViewModelStatusRefreshResult = Interfaces.RuntimeViewModelStatusRefreshResult
typealias RuntimeViewModelStatusRefresher = Interfaces.RuntimeViewModelStatusRefresher

extension RuntimeViewModelSnapshotLoader: RuntimeViewModelStatusSnapshotLoading {}
extension RuntimePresentationFormatter: RuntimeViewModelStatusPresentationFormatting {}

extension RuntimeViewModelStatusRefresher {
    init(
        snapshots: any RuntimeViewModelStatusSnapshotLoading,
        formatter: RuntimePresentationFormatter = RuntimePresentationFormatter()
    ) {
        self.init(snapshots: snapshots, formatter: formatter as any RuntimeViewModelStatusPresentationFormatting)
    }
}
