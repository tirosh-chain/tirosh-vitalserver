import AppKit
import SwiftUI

struct InstallWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = InstallSettings()
    @State private var step = 0
    @State private var validationMessage: String?

    private let finalStep = 7
    let onInstall: (InstallSettings) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            Divider()
            stepContent
                .frame(minHeight: 260, alignment: .topLeading)
            Divider()
            footer
        }
        .padding(24)
        .frame(width: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppConstants.Actions.installRuntime)
                .font(.title2)
                .fontWeight(.semibold)
            Text(AppConstants.StatusText.installWizardIntro)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            profileStep
        case 1:
            storageStep
        case 2:
            networkStep
        case 3:
            dataStep
        case 4:
            accountStep
        case 5:
            advancedStep
        case 6:
            serviceStep
        default:
            reviewStep
        }
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(AppConstants.Labels.installProfile)
            Picker(AppConstants.Labels.installProfile, selection: profileSelection) {
                ForEach(RuntimeProfile.allCases) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(RuntimeProfile.allCases) { profile in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: settings.profile == profile ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(settings.profile == profile ? Color.accentColor : Color.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.title)
                                .fontWeight(.semibold)
                            Text(profile.specLine)
                                .font(.callout)
                            Text(profile.description)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        profileSelection.wrappedValue = profile
                    }
                }
            }
        }
    }

    private var storageStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(AppConstants.Labels.storage)
            Text(AppConstants.InstallWizard.cpuRequirement)
                .foregroundStyle(.secondary)

            if settings.profile == .recommended {
                Text(settings.resources.summary)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(AppConstants.InstallWizard.recommendedResourcesLocked)
                    .foregroundStyle(.secondary)
            } else {
                resourceSlider(
                    title: AppConstants.InstallWizard.cpu,
                    value: $settings.resources.cpuCount,
                    range: 7...maxSelectableCPUCount,
                    step: 1,
                    suffix: "vCPU"
                )
                resourceSlider(
                    title: AppConstants.InstallWizard.memory,
                    value: $settings.resources.memoryGiB,
                    range: 4...64,
                    step: 4,
                    suffix: "GB"
                )
                resourceSlider(
                    title: AppConstants.InstallWizard.diskSize,
                    value: $settings.resources.diskGiB,
                    range: 32...512,
                    step: 16,
                    suffix: "GB"
                )
            }
        }
    }

    private var networkStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(AppConstants.Labels.network)
            Picker(AppConstants.Labels.network, selection: networkSelection) {
                Text(RuntimeNetworkMode.shared.title).tag(RuntimeNetworkMode.shared)
                Text(RuntimeNetworkMode.bridged.title).tag(RuntimeNetworkMode.bridged)
            }
            .pickerStyle(.radioGroup)

            Text(AppConstants.InstallWizard.bridgedUnavailable)
                .foregroundStyle(.secondary)

            Divider()

            Stepper(
                "\(AppConstants.InstallWizard.hostProxyPort): \(settings.proxyPort)",
                value: $settings.proxyPort,
                in: 1...65535
            )
            Text(AppConstants.InstallWizard.sharedNetworkAddressing)
                .foregroundStyle(.secondary)
        }
    }

    private var serviceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(AppConstants.Labels.service)
            Toggle(AppConstants.InstallWizard.startAfterInstall, isOn: $settings.startAfterInstall)
            Toggle(AppConstants.InstallWizard.startOnBoot, isOn: $settings.startOnBoot)
            Text("These settings are applied by the installer after administrator approval.")
                .foregroundStyle(.secondary)
        }
    }

    private var dataStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(AppConstants.Labels.data)
            TextField(AppConstants.InstallWizard.vitalFilesDirectory, text: $settings.vitalFilesDirectory)
                .textFieldStyle(.roundedBorder)
            Button(AppConstants.InstallWizard.choose) {
                chooseVitalFilesDirectory()
            }
            Text(AppConstants.InstallWizard.vitalFilesDirectoryDescription)
                .foregroundStyle(.secondary)
        }
    }

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(AppConstants.Labels.account)
            SecureField(AppConstants.InstallWizard.adminPassword, text: $settings.adminPassword)
                .textFieldStyle(.roundedBorder)
            SecureField(AppConstants.InstallWizard.confirmAdminPassword, text: $settings.adminPasswordConfirmation)
                .textFieldStyle(.roundedBorder)
            Text(AppConstants.InstallWizard.adminPasswordDescription)
                .foregroundStyle(.secondary)
            if let validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.red)
            }
        }
    }

    private var advancedStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(AppConstants.Labels.advanced)
            Text(AppConstants.InstallWizard.advancedDescription)
                .foregroundStyle(.secondary)
            TextField(AppConstants.InstallWizard.vmHostname, text: $settings.vmHostname)
                .textFieldStyle(.roundedBorder)
            Divider()
            TextField(AppConstants.InstallWizard.publicHost, text: $settings.publicHost)
                .textFieldStyle(.roundedBorder)
            Stepper(
                "\(AppConstants.InstallWizard.publicPort): \(settings.publicPort)",
                value: $settings.publicPort,
                in: 1...65535
            )
            Text(AppConstants.InstallWizard.publicHostDescription)
                .foregroundStyle(.secondary)
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(AppConstants.Labels.review)
            ForEach(settings.summaryLines, id: \.self) { line in
                Text(line)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(AppConstants.Actions.cancel) {
                dismiss()
            }
            Spacer()
            Button(AppConstants.Actions.back) {
                step = previousStep(from: step)
            }
            .disabled(step == 0)
            Button(step == finalStep ? AppConstants.Actions.install : AppConstants.Actions.continueAction) {
                if step == finalStep {
                    if let message = settings.validationMessage {
                        validationMessage = message
                    } else {
                        onInstall(settings)
                        dismiss()
                    }
                } else {
                    if step == 4, let message = settings.validationMessage {
                        validationMessage = message
                        return
                    }
                    validationMessage = nil
                    step = nextStep(from: step)
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value)
            .font(.headline)
    }

    private var maxSelectableCPUCount: Int {
        min(64, max(16, ProcessInfo.processInfo.processorCount))
    }

    private func nextStep(from current: Int) -> Int {
        if current == 0, settings.profile == .recommended {
            return 2
        }
        return min(current + 1, finalStep)
    }

    private func previousStep(from current: Int) -> Int {
        if current == 2, settings.profile == .recommended {
            return 0
        }
        return max(current - 1, 0)
    }

    private var profileSelection: Binding<RuntimeProfile> {
        Binding(
            get: { settings.profile },
            set: { value in
                settings.profile = value
                settings.applyProfileDefaults()
            }
        )
    }

    private var networkSelection: Binding<RuntimeNetworkMode> {
        Binding(
            get: { settings.networkMode },
            set: { value in
                settings.networkMode = value == .bridged ? .shared : value
            }
        )
    }

    private func chooseVitalFilesDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = AppConstants.InstallWizard.choose

        if panel.runModal() == .OK, let url = panel.url {
            settings.vitalFilesDirectory = url.path
        }
    }

    private func resourceSlider(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        suffix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .fontWeight(.medium)
                Spacer()
                Text("\(value.wrappedValue) \(suffix)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding<Double>(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            HStack {
                Text("\(range.lowerBound)")
                Spacer()
                Text("\(range.upperBound)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
