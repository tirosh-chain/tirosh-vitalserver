import Application
import Contracts
import Foundation
import SQLite3

public enum SQLiteHostPlatformInstallationRepositoryError:
  Error,
  Equatable,
  Sendable
{
  case installationAlreadyInitialized
  case installationMissing
  case activeOperationExists(String)
  case operationMissing(String)
  case operationAlreadyExists(String)
  case staleOperationRevision(expected: Int, actual: Int)
  case staleInstallationRevision(expected: Int, actual: Int)
  case operationIsNotActive(String)
  case invalidDocument(reason: String)
  case databaseFailed(path: String, reason: String)
}

public struct SQLiteHostPlatformInstallationRepository:
  HostPlatformInstallationRepository,
  @unchecked Sendable
{
  public let databaseURL: URL
  private let connection: SQLiteHostRuntimeStateConnection
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let validateManifest: (HostPlatformInstallationManifest) throws -> Void
  private let validateOperation: (HostPlatformInstallationOperation) throws -> Void
  private let validateTransition:
    (
      HostPlatformInstallationOperation,
      HostPlatformInstallationOperation
    ) throws -> Void

  public init(
    databaseURL: URL,
    busyTimeoutMilliseconds: Int32 = 5_000,
    encoder: JSONEncoder = JSONEncoder(),
    decoder: JSONDecoder = JSONDecoder(),
    validateManifest: @escaping (HostPlatformInstallationManifest) throws -> Void,
    validateOperation: @escaping (HostPlatformInstallationOperation) throws -> Void,
    validateTransition:
      @escaping (
        HostPlatformInstallationOperation,
        HostPlatformInstallationOperation
      ) throws -> Void
  ) {
    self.databaseURL = databaseURL
    self.connection = SQLiteHostRuntimeStateConnection(
      url: databaseURL,
      busyTimeoutMilliseconds: busyTimeoutMilliseconds
    )
    self.encoder = encoder
    self.decoder = decoder
    self.validateManifest = validateManifest
    self.validateOperation = validateOperation
    self.validateTransition = validateTransition
  }

  public func initializeInstallation(
    _ manifest: HostPlatformInstallationManifest
  ) throws {
    do {
      try validateManifest(manifest)
      guard manifest.installationRevision == 1 else {
        throw
          SQLiteHostPlatformInstallationRepositoryError
          .staleInstallationRevision(
            expected: 1,
            actual: manifest.installationRevision
          )
      }
      try FileManager.default.createDirectory(
        at: databaseURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try connection.withWritableDatabase { db in
        try createSchema(db)
        try connection.withImmediateTransaction(db) {
          guard try activeManifestRevision(db) == nil else {
            throw SQLiteHostPlatformInstallationRepositoryError
              .installationAlreadyInitialized
          }
          try insertManifest(manifest, db: db)
        }
      }
    } catch let error as SQLiteHostPlatformInstallationRepositoryError {
      throw error
    } catch {
      throw databaseError(error)
    }
  }

  public func loadActiveInstallation() -> HostPlatformInstallationManifestReadResult {
    do {
      return try connection.withReadOnlyDatabase { db in
        try validateSchema(db)
        guard
          let document =
            try SQLiteHostRuntimeStateStatement
            .scalarString(
              db,
              sql: """
                SELECT document_json
                FROM host_platform_active_installation
                WHERE singleton_id = 1
                """
            )
        else {
          return .missing
        }
        let manifest = try decoder.decode(
          HostPlatformInstallationManifest.self,
          from: Data(document.utf8)
        )
        try validateManifest(manifest)
        return .loaded(manifest)
      }
    } catch {
      return .failed(reason: databaseReason(error))
    }
  }

  public func loadOperation(
    id: String
  ) -> HostPlatformInstallationOperationReadResult {
    do {
      return try connection.withReadOnlyDatabase { db in
        try validateSchema(db)
        guard
          let document =
            try SQLiteHostRuntimeStateStatement
            .scalarString(
              db,
              sql: """
                SELECT document_json
                FROM host_platform_installation_operations
                WHERE operation_id = ?
                """,
              bindings: [.text(id)]
            )
        else {
          return .missing
        }
        let operation = try decoder.decode(
          HostPlatformInstallationOperation.self,
          from: Data(document.utf8)
        )
        try validateOperation(operation)
        return .loaded(operation)
      }
    } catch {
      return .failed(reason: databaseReason(error))
    }
  }

  public func beginOperation(
    _ operation: HostPlatformInstallationOperation
  ) throws {
    do {
      try validateOperation(operation)
      try connection.withWritableDatabase { db in
        try validateSchema(db)
        try connection.withImmediateTransaction(db) {
          guard let fence = try activeInstallationFence(db) else {
            throw SQLiteHostPlatformInstallationRepositoryError
              .installationMissing
          }
          guard fence.installationId == operation.installationId else {
            throw
              SQLiteHostPlatformInstallationRepositoryError
              .invalidDocument(
                reason:
                  "installation identity expected=\(operation.installationId) actual=\(fence.installationId)"
              )
          }
          guard fence.revision == operation.expectedInstallationRevision else {
            throw
              SQLiteHostPlatformInstallationRepositoryError
              .staleInstallationRevision(
                expected: operation.expectedInstallationRevision,
                actual: fence.revision
              )
          }
          if let active = try activeOperationId(db) {
            throw
              SQLiteHostPlatformInstallationRepositoryError
              .activeOperationExists(active)
          }
          guard
            try operationRevision(
              operation.id,
              db: db
            ) == nil
          else {
            throw
              SQLiteHostPlatformInstallationRepositoryError
              .operationAlreadyExists(operation.id)
          }
          try insertOperation(operation, db: db)
          try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
              INSERT INTO host_platform_active_operation(
                singleton_id, operation_id
              ) VALUES(1, ?)
              """,
            bindings: [.text(operation.id)]
          )
        }
      }
    } catch let error as SQLiteHostPlatformInstallationRepositoryError {
      throw error
    } catch {
      throw databaseError(error)
    }
  }

  public func saveOperation(
    _ operation: HostPlatformInstallationOperation,
    expectedOperationRevision: Int
  ) throws {
    try updateOperation(
      operation,
      expectedOperationRevision: expectedOperationRevision,
      terminal: false
    )
  }

  public func settleSucceededOperation(
    _ operation: HostPlatformInstallationOperation,
    activeManifest: HostPlatformInstallationManifest,
    expectedOperationRevision: Int,
    expectedInstallationRevision: Int
  ) throws {
    do {
      try validateOperation(operation)
      try validateManifest(activeManifest)
      guard operation.state == .succeeded,
        activeManifest.activationOperationId == operation.id,
        activeManifest.installationId == operation.installationId,
        activeManifest.installationRevision == expectedInstallationRevision + 1,
        activeManifest.activeRelease == operation.targetRelease
      else {
        throw
          SQLiteHostPlatformInstallationRepositoryError
          .invalidDocument(reason: "invalid succeeded settlement")
      }
      try connection.withWritableDatabase { db in
        try validateSchema(db)
        try connection.withImmediateTransaction(db) {
          try requireActiveOperation(operation.id, db: db)
          try requireOperationRevision(
            operation.id,
            expected: expectedOperationRevision,
            db: db
          )
          guard let fence = try activeInstallationFence(db) else {
            throw SQLiteHostPlatformInstallationRepositoryError
              .installationMissing
          }
          guard fence.installationId == operation.installationId else {
            throw
              SQLiteHostPlatformInstallationRepositoryError
              .invalidDocument(
                reason:
                  "installation identity expected=\(operation.installationId) actual=\(fence.installationId)"
              )
          }
          guard fence.revision == expectedInstallationRevision else {
            throw
              SQLiteHostPlatformInstallationRepositoryError
              .staleInstallationRevision(
                expected: expectedInstallationRevision,
                actual: fence.revision
              )
          }
          try validateStoredTransition(operation, db: db)
          try replaceOperation(operation, db: db)
          try replaceManifest(activeManifest, db: db)
          try clearActiveOperation(operation.id, db: db)
        }
      }
    } catch let error as SQLiteHostPlatformInstallationRepositoryError {
      throw error
    } catch {
      throw databaseError(error)
    }
  }

  public func settleFailedOperation(
    _ operation: HostPlatformInstallationOperation,
    expectedOperationRevision: Int
  ) throws {
    try updateOperation(
      operation,
      expectedOperationRevision: expectedOperationRevision,
      terminal: true
    )
  }

  private func updateOperation(
    _ operation: HostPlatformInstallationOperation,
    expectedOperationRevision: Int,
    terminal: Bool
  ) throws {
    do {
      try validateOperation(operation)
      guard terminal == (operation.state == .failed) else {
        throw
          SQLiteHostPlatformInstallationRepositoryError
          .invalidDocument(reason: "terminal state mismatch")
      }
      try connection.withWritableDatabase { db in
        try validateSchema(db)
        try connection.withImmediateTransaction(db) {
          try requireActiveOperation(operation.id, db: db)
          try requireOperationRevision(
            operation.id,
            expected: expectedOperationRevision,
            db: db
          )
          try validateStoredTransition(operation, db: db)
          try replaceOperation(operation, db: db)
          if terminal {
            try clearActiveOperation(operation.id, db: db)
          }
        }
      }
    } catch let error as SQLiteHostPlatformInstallationRepositoryError {
      throw error
    } catch {
      throw databaseError(error)
    }
  }

  private func createSchema(_ db: OpaquePointer) throws {
    let statements = [
      """
      CREATE TABLE IF NOT EXISTS host_platform_manager_metadata(
        singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
        schema_version INTEGER NOT NULL
      )
      """,
      """
      INSERT OR IGNORE INTO host_platform_manager_metadata(
        singleton_id, schema_version
      ) VALUES(1, 1)
      """,
      """
      CREATE TABLE IF NOT EXISTS host_platform_active_installation(
        singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
        installation_id TEXT NOT NULL,
        installation_revision INTEGER NOT NULL,
        document_json TEXT NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS host_platform_installation_operations(
        operation_id TEXT PRIMARY KEY,
        operation_revision INTEGER NOT NULL,
        state TEXT NOT NULL,
        document_json TEXT NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS host_platform_active_operation(
        singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
        operation_id TEXT NOT NULL UNIQUE,
        FOREIGN KEY(operation_id)
          REFERENCES host_platform_installation_operations(operation_id)
      )
      """,
    ]
    for statement in statements {
      try SQLiteHostRuntimeStateStatement.execute(db, sql: statement)
    }
  }

  private func validateSchema(_ db: OpaquePointer) throws {
    let version = try SQLiteHostRuntimeStateStatement.scalarInt(
      db,
      sql: """
        SELECT schema_version
        FROM host_platform_manager_metadata
        WHERE singleton_id = 1
        """
    )
    guard version == 1 else {
      throw
        SQLiteHostPlatformInstallationRepositoryError
        .invalidDocument(
          reason: "schema version expected=1 actual=\(version.map(String.init) ?? "missing")"
        )
    }
  }

  private func activeManifestRevision(_ db: OpaquePointer) throws -> Int? {
    try SQLiteHostRuntimeStateStatement.scalarInt(
      db,
      sql: """
        SELECT installation_revision
        FROM host_platform_active_installation
        WHERE singleton_id = 1
        """
    )
  }

  private func activeInstallationFence(
    _ db: OpaquePointer
  ) throws -> (installationId: String, revision: Int)? {
    guard
      let row = try SQLiteHostRuntimeStateStatement.stringRow(
        db,
        sql: """
          SELECT installation_id, installation_revision
          FROM host_platform_active_installation
          WHERE singleton_id = 1
          """,
        columnCount: 2
      )
    else {
      return nil
    }
    guard let installationId = row[0],
      let revisionText = row[1],
      let revision = Int(revisionText)
    else {
      throw
        SQLiteHostPlatformInstallationRepositoryError
        .invalidDocument(reason: "active installation fence is invalid")
    }
    return (installationId, revision)
  }

  private func activeOperationId(_ db: OpaquePointer) throws -> String? {
    try SQLiteHostRuntimeStateStatement.scalarString(
      db,
      sql: """
        SELECT operation_id
        FROM host_platform_active_operation
        WHERE singleton_id = 1
        """
    )
  }

  private func operationRevision(
    _ id: String,
    db: OpaquePointer
  ) throws -> Int? {
    try SQLiteHostRuntimeStateStatement.scalarInt(
      db,
      sql: """
        SELECT operation_revision
        FROM host_platform_installation_operations
        WHERE operation_id = ?
        """,
      bindings: [.text(id)]
    )
  }

  private func requireActiveOperation(
    _ id: String,
    db: OpaquePointer
  ) throws {
    guard let active = try activeOperationId(db) else {
      throw
        SQLiteHostPlatformInstallationRepositoryError
        .operationIsNotActive(id)
    }
    guard active == id else {
      throw
        SQLiteHostPlatformInstallationRepositoryError
        .activeOperationExists(active)
    }
  }

  private func requireOperationRevision(
    _ id: String,
    expected: Int,
    db: OpaquePointer
  ) throws {
    guard let actual = try operationRevision(id, db: db) else {
      throw
        SQLiteHostPlatformInstallationRepositoryError
        .operationMissing(id)
    }
    guard actual == expected else {
      throw
        SQLiteHostPlatformInstallationRepositoryError
        .staleOperationRevision(expected: expected, actual: actual)
    }
  }

  private func validateStoredTransition(
    _ next: HostPlatformInstallationOperation,
    db: OpaquePointer
  ) throws {
    guard
      let document = try SQLiteHostRuntimeStateStatement.scalarString(
        db,
        sql: """
          SELECT document_json
          FROM host_platform_installation_operations
          WHERE operation_id = ?
          """,
        bindings: [.text(next.id)]
      )
    else {
      throw
        SQLiteHostPlatformInstallationRepositoryError
        .operationMissing(next.id)
    }
    let previous = try decoder.decode(
      HostPlatformInstallationOperation.self,
      from: Data(document.utf8)
    )
    try validateTransition(previous, next)
  }

  private func insertManifest(
    _ manifest: HostPlatformInstallationManifest,
    db: OpaquePointer
  ) throws {
    try SQLiteHostRuntimeStateStatement.execute(
      db,
      sql: """
        INSERT INTO host_platform_active_installation(
          singleton_id, installation_id, installation_revision, document_json
        ) VALUES(1, ?, ?, ?)
        """,
      bindings: [
        .text(manifest.installationId),
        .int(manifest.installationRevision),
        .text(try encode(manifest)),
      ]
    )
  }

  private func replaceManifest(
    _ manifest: HostPlatformInstallationManifest,
    db: OpaquePointer
  ) throws {
    try SQLiteHostRuntimeStateStatement.execute(
      db,
      sql: """
        UPDATE host_platform_active_installation
        SET installation_id = ?,
            installation_revision = ?,
            document_json = ?
        WHERE singleton_id = 1
        """,
      bindings: [
        .text(manifest.installationId),
        .int(manifest.installationRevision),
        .text(try encode(manifest)),
      ]
    )
  }

  private func insertOperation(
    _ operation: HostPlatformInstallationOperation,
    db: OpaquePointer
  ) throws {
    try SQLiteHostRuntimeStateStatement.execute(
      db,
      sql: """
        INSERT INTO host_platform_installation_operations(
          operation_id, operation_revision, state, document_json
        ) VALUES(?, ?, ?, ?)
        """,
      bindings: operationBindings(operation)
    )
  }

  private func replaceOperation(
    _ operation: HostPlatformInstallationOperation,
    db: OpaquePointer
  ) throws {
    try SQLiteHostRuntimeStateStatement.execute(
      db,
      sql: """
        UPDATE host_platform_installation_operations
        SET operation_revision = ?, state = ?, document_json = ?
        WHERE operation_id = ?
        """,
      bindings: [
        .int(operation.operationRevision),
        .text(operation.state.rawValue),
        .text(try encode(operation)),
        .text(operation.id),
      ]
    )
  }

  private func operationBindings(
    _ operation: HostPlatformInstallationOperation
  ) throws -> [SQLiteHostRuntimeStateBinding] {
    [
      .text(operation.id),
      .int(operation.operationRevision),
      .text(operation.state.rawValue),
      .text(try encode(operation)),
    ]
  }

  private func clearActiveOperation(
    _ id: String,
    db: OpaquePointer
  ) throws {
    try SQLiteHostRuntimeStateStatement.execute(
      db,
      sql: """
        DELETE FROM host_platform_active_operation
        WHERE singleton_id = 1 AND operation_id = ?
        """,
      bindings: [.text(id)]
    )
  }

  private func encode<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try encoder.encode(value), as: UTF8.self)
  }

  private func databaseError(
    _ error: Error
  ) -> SQLiteHostPlatformInstallationRepositoryError {
    .databaseFailed(
      path: databaseURL.path,
      reason: String(describing: error)
    )
  }

  private func databaseReason(_ error: Error) -> String {
    "Host Platform Installation Manager SQLite read failed path=\(databaseURL.path) reason=\(error)"
  }
}
