import Application
import Contracts
import Foundation

public struct ReceiptWritingHostPlatformServiceReconciler:
  HostPlatformServiceReconciling,
  @unchecked Sendable
{
  public let executableURL: URL
  public let exchangeRoot: URL
  private let processFactory: () -> Process

  public init(
    executableURL: URL,
    exchangeRoot: URL,
    processFactory: @escaping () -> Process = Process.init
  ) {
    self.executableURL = executableURL
    self.exchangeRoot = exchangeRoot
    self.processFactory = processFactory
  }

  public func reconcileServices(
    request: HostPlatformServiceReconciliationRequest
  ) -> HostPlatformServiceReconciliationResult {
    let operationRoot = exchangeRoot.appendingPathComponent(
      request.reconciliationId,
      isDirectory: true
    )
    let requestURL = operationRoot.appendingPathComponent("request.json")
    let receiptURL = operationRoot.appendingPathComponent("receipt.json")
    do {
      try FileManager.default.createDirectory(
        at: operationRoot,
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: receiptURL.path) {
        return try readReceipt(receiptURL)
      }
      try JSONEncoder().encode(request).write(
        to: requestURL,
        options: [.atomic]
      )

      let process = processFactory()
      process.executableURL = executableURL
      process.arguments = [
        "reconcile",
        "--request", requestURL.path,
        "--receipt", receiptURL.path,
      ]
      try process.run()
      process.waitUntilExit()

      guard FileManager.default.fileExists(atPath: receiptURL.path) else {
        return .failed(
          reason: [
            "service reconciler produced no receipt",
            "path=\(receiptURL.path)",
            "processTerminationStatus=\(process.terminationStatus)",
          ].joined(separator: " ")
        )
      }
      return try readReceipt(receiptURL)
    } catch {
      return .failed(
        reason: "service reconciliation invocation failed reason=\(error)"
      )
    }
  }

  private func readReceipt(
    _ receiptURL: URL
  ) throws -> HostPlatformServiceReconciliationResult {
    let receipt = try JSONDecoder().decode(
      HostPlatformServiceReconciliationReceipt.self,
      from: Data(contentsOf: receiptURL)
    )
    return .completed(receipt)
  }
}
