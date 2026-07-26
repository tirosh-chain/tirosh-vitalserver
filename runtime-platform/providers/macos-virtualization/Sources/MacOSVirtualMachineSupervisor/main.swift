import Foundation
import MacOSVirtualizationProvider

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2, arguments[0] == "--virtual-machine-configuration" else {
    FileHandle.standardError.write(Data("macOS virtual machine supervisor requires one --virtual-machine-configuration path\n".utf8))
    exit(2)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let decoder = JSONDecoder()

do {
    // The controller is deliberately created once and retained by this
    // long-lived process. A C21 invocation must never create a temporary
    // VZVirtualMachine whose owner disappears after one stdout response.
    let configuration = try MacOSVirtualMachineConfigurationLoader.load(fromFile: arguments[1])
    let controller = try ProvisionedMacOSVirtualMachineFactory.makeController(document: configuration)
    let executor = LifecycleExecutor(controller: controller)

    while let line = readLine(strippingNewline: true) {
        guard !line.isEmpty else {
            continue
        }
        guard let invocationData = line.data(using: .utf8),
              let invocation = try? decoder.decode(PlatformProviderLifecycleInvocation.self, from: invocationData),
              invocation.isValidForMacOSVirtualization else {
            FileHandle.standardError.write(Data("macOS virtual machine supervisor rejected an invalid C21 lifecycle invocation\n".utf8))
            continue
        }
        let result = executor.execute(invocation.lifecycle)
        let output = try encoder.encode(result)
        FileHandle.standardOutput.write(output)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
} catch let error as MacOSVirtualMachineConfigurationError {
    FileHandle.standardError.write(Data("macOS virtual machine supervisor configuration failed: \(error.localizedDescription)\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("macOS virtual machine supervisor failed to initialize\n".utf8))
    exit(1)
}
