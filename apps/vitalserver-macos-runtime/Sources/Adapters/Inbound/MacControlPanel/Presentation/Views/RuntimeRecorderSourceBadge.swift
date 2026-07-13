import SwiftUI

struct RuntimeRecorderSourceBadge: View {
    let version: String?
    private let displayPolicy = RuntimeVitalRecorderDisplayPolicy()

    var body: some View {
        let source = displayPolicy.recorderSourceText(version)
        if displayPolicy.isProductLabRecorder(version: version) {
            Text(source)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.purple)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.purple.opacity(0.10))
                .clipShape(Capsule())
                .accessibilityLabel("Recorder source: \(source)")
        } else {
            Text(source)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel("Recorder source: \(source)")
        }
    }
}
