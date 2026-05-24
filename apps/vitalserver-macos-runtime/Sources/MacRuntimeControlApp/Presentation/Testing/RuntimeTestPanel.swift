import SwiftUI

struct RuntimeTestPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppConstants.Labels.testSummary)
                        .font(.headline)
                    Text(AppConstants.Labels.testDescription)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                browserCard
                testkitCard
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(16)
        }
    }

    private var browserCard: some View {
        testCard(AppConstants.Labels.sectionBrowserChecks) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                statusRow(AppConstants.Labels.runtimeControlConsole) {
                    linkButton(AppConstants.RuntimeControlAPI.devConsoleURL) {
                        viewModel.openRuntimeControlDevConsole()
                    }
                    .help(AppConstants.Labels.runtimeControlConsoleHelp)
                }
            }
        }
    }

    private var testkitCard: some View {
        testCard(AppConstants.Labels.testkitService) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                statusRow(AppConstants.Labels.serviceBundled) {
                    Text(GeneratedRelease.testkitContainerIncluded ? AppConstants.Values.boolTrue : AppConstants.Values.boolFalse)
                        .fontWeight(.medium)
                }
            }
        }
    }

    private func testCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(.link)
    }
}
