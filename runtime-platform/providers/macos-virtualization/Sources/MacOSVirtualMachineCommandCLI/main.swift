import Foundation
import MacOSVirtualizationProvider

let input = FileHandle.standardInput.readDataToEndOfFile()
let decoder = JSONDecoder()
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]

let commandLineArguments = Array(CommandLine.arguments.dropFirst())
var virtualMachineConfigurationPath: String?
var argumentIndex = 0
while argumentIndex < commandLineArguments.count {
    guard commandLineArguments[argumentIndex] == "--virtual-machine-configuration", argumentIndex + 1 < commandLineArguments.count, virtualMachineConfigurationPath == nil else {
        FileHandle.standardError.write(Data("macOS virtual machine command CLI accepts only one --virtual-machine-configuration path\n".utf8))
        exit(2)
    }
    virtualMachineConfigurationPath = commandLineArguments[argumentIndex + 1]
    argumentIndex += 2
}

do {
    let invocation = try decoder.decode(PlatformProviderLifecycleInvocation.self, from: input)
    guard invocation.isValidForMacOSVirtualization else {
        throw NSError(domain: "MacOSVirtualMachineCommandCLI", code: 2)
    }
    let controller: (any VirtualMachineControlling)?
    if let virtualMachineConfigurationPath {
        let document = try MacOSVirtualMachineConfigurationLoader.load(fromFile: virtualMachineConfigurationPath)
        controller = try ProvisionedMacOSVirtualMachineFactory.makeController(document: document)
    } else {
        controller = nil
    }
    let result = LifecycleExecutor(controller: controller).execute(invocation.lifecycle)
    let output = try encoder.encode(result)
    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch let error as MacOSVirtualMachineConfigurationError {
    let invocation = try? decoder.decode(PlatformProviderLifecycleInvocation.self, from: input)
    if let invocation {
        let state: String
        let retryable: Bool
        switch error {
        case .unavailable:
            state = "unavailable"
            retryable = true
        case .invalid:
            state = "failed"
            retryable = false
        }
        let result = ProviderLifecycleResult(
            requestId: invocation.lifecycle.requestId,
            providerId: invocation.lifecycle.providerId,
            observedState: state,
            observedAt: ISO8601DateFormatter().string(from: Date()),
            issue: ProviderIssue(code: "macos-vm-configuration-" + state, message: error.localizedDescription, retryable: retryable, dependency: "macos-virtualization")
        )
        let output = try encoder.encode(result)
        FileHandle.standardOutput.write(output)
        FileHandle.standardOutput.write(Data("\n".utf8))
    } else {
        FileHandle.standardError.write(Data("macOS virtual machine command CLI could not decode a valid C21 lifecycle invocation\n".utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("macOS virtual machine command CLI could not decode a valid C21 lifecycle invocation\n".utf8))
    exit(2)
}
