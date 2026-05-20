import SwiftUI

struct InstallerView: View {
    @StateObject private var controller = InstallerController()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            progressPanel
            settingsForm
            actionBar
            logPanel
        }
        .frame(width: 680)
        .padding(24)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Configure & Install Tirosh VitalServer")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Set the runtime policy before installing the product package.")
                .foregroundStyle(.secondary)
        }
    }

    private var settingsForm: some View {
        Form {
            Stepper(value: $controller.settings.cpuCount, in: 7...64) {
                labeledValue("CPU", "\(controller.settings.cpuCount)")
            }
            Stepper(value: $controller.settings.memoryGiB, in: 4...64, step: 4) {
                labeledValue("Memory", "\(controller.settings.memoryGiB) GiB")
            }
            Stepper(value: $controller.settings.diskGiB, in: 32...512, step: 16) {
                labeledValue("VM disk", "\(controller.settings.diskGiB) GiB")
            }
            Picker("Network", selection: $controller.settings.networkMode) {
                Text("Shared").tag("shared")
                Text("Bridged").tag("bridged")
            }
            Stepper(value: $controller.settings.proxyPort, in: 1...65_535) {
                labeledValue("Proxy port", "\(controller.settings.proxyPort)")
            }
            HStack {
                TextField("Vital files directory", text: $controller.settings.vitalFilesDirectory)
                Button("Choose") {
                    controller.chooseVitalFilesDirectory()
                }
            }
            TextField("VM hostname", text: $controller.settings.vmHostname)
            TextField("Public host", text: $controller.settings.publicHost)
            Stepper(value: $controller.settings.publicPort, in: 1...65_535) {
                labeledValue("Public port", "\(controller.settings.publicPort)")
            }
            SecureField("Admin password", text: $controller.settings.adminPassword)
            Toggle("Start after install", isOn: $controller.settings.startAfterInstall)
            Toggle("Start on boot", isOn: $controller.settings.startOnBoot)
        }
    }

    private var actionBar: some View {
        HStack {
            Button("Validate") {
                controller.revalidate()
            }
            .disabled(controller.isBusy)
            Button("Open Install Log") {
                controller.openInstallLog()
            }
            Spacer()
            Button("Install") {
                Task { await controller.install() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(controller.isBusy)
        }
    }

    private var progressPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(controller.stage)
                    .fontWeight(.semibold)
                Spacer()
                if controller.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if !controller.validationIssues.isEmpty {
                ForEach(controller.validationIssues, id: \.self) { issue in
                    Text(issue)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var logPanel: some View {
        ScrollView {
            Text(controller.message)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(minHeight: 90)
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
