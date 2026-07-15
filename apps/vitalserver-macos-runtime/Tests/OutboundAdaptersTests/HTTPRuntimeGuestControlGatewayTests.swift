import Application
import Contracts
import Foundation
import OutboundAdapters
import RuntimeControl
import XCTest

final class HTTPRuntimeGuestControlGatewayTests: XCTestCase {
    func testGatewayErrorLocalizedDescriptionPreservesTypedFailureReason() {
        let error = RuntimeGuestControlHTTPGatewayError.decodeFailed("missing field services")
        XCTAssertEqual(
            error.localizedDescription,
            "guest control API response decode failed: missing field services"
        )
    }

    func testReadyRequestsGuestControlReadyEndpoint() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "status": "ready",
              "dependencies": [
                {
                  "name": "operationRepository",
                  "role": "required",
                  "state": "ready",
                  "kind": null,
                  "message": null
                }
              ]
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let result = try gateway.ready()

        XCTAssertEqual(
            result,
            RuntimeGuestControlReadiness(
                status: "ready",
                dependencies: [
                    RuntimeGuestControlReadinessDependency(
                        name: "operationRepository",
                        role: "required",
                        state: "ready"
                    )
                ]
            )
        )
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/ready"])
    }

    func testRequestsUseConfiguredTimeout() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "status": "ready",
              "dependencies": []
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client,
            timeout: 5
        )

        _ = try gateway.ready()

        XCTAssertEqual(client.requests.first?.timeoutInterval, 5)
    }

    func testReadyDecodesDependencyFailureDocumentFromServiceUnavailableResponse() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 503,
            body: """
            {
              "status": "unavailable",
              "dependencies": [
                {
                  "name": "operationRepository",
                  "role": "required",
                  "state": "failed",
                  "kind": "postgresCommandFailed",
                  "message": "postgres command failed during readiness"
                }
              ]
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let result = try gateway.ready()

        XCTAssertEqual(result.status, "unavailable")
        XCTAssertEqual(result.dependencies, [
            RuntimeGuestControlReadinessDependency(
                name: "operationRepository",
                role: "required",
                state: "failed",
                kind: "postgresCommandFailed",
                message: "postgres command failed during readiness"
            )
        ])
    }

    func testCapabilitiesRequestsGuestControlCapabilitiesEndpoint() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "schemaVersion": 1,
              "capabilities": [
                "services:list",
                "maintenance:update-shutdown:create"
              ]
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let result = try gateway.capabilities()

        XCTAssertEqual(result.schemaVersion, 1)
        XCTAssertEqual(result.capabilities, [
            "services:list",
            "maintenance:update-shutdown:create",
        ])
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/runtime/capabilities"])
    }

    func testRuntimeSettingsReadIsOwnedByGuestController() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: #"{"state":"failed","settings":null,"readError":"settings file is invalid"}"#
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let read = try gateway.runtimeSettings()

        XCTAssertEqual(read.state, .failed)
        XCTAssertNil(read.settings)
        XCTAssertEqual(read.readError, "settings file is invalid")
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/settings"]
        )
    }

    func testApplyRuntimeSettingsUsesGuestProductContract() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 202,
            body: """
            {
              "operationId": "runtime-settings-1",
              "service": "runtime-settings",
              "command": "apply-settings",
              "state": "completed",
              "createdAt": "2026-07-01T00:00:00+00:00",
              "updatedAt": "2026-07-01T00:00:01+00:00"
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )
        let settings = GuestRuntimeSettingsDocument(
            vitalServerURL: "http://vitalserver.local/",
            remoteConsoleURL: "http://console.local/",
            publicHost: "vitalserver.local",
            publicPort: 80
        )

        let operation = try gateway.applyRuntimeSettings(settings)

        XCTAssertEqual(operation.command, .applySettings)
        XCTAssertEqual(client.requests.map(\.httpMethod), ["PUT"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/settings"]
        )
        let body = try XCTUnwrap(client.requests.first?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let encodedSettings = try XCTUnwrap(object["settings"] as? [String: Any])
        XCTAssertEqual(encodedSettings["publicHost"] as? String, "vitalserver.local")
    }

    func testApplyAdminPasswordUsesRuntimeOwnerCommandWithoutReturningSecret() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 202,
            body: """
            {
              "operationId": "runtime-admin-1",
              "service": "runtime-admin",
              "command": "apply-admin-password",
              "state": "completed",
              "createdAt": "2026-07-01T00:00:00+00:00",
              "updatedAt": "2026-07-01T00:00:01+00:00"
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let operation = try gateway.applyAdminPassword("new-admin-secret")

        XCTAssertEqual(operation.command, .applyAdminPassword)
        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/admin-password"]
        )
        let body = try XCTUnwrap(client.requests.first?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["password"] as? String, "new-admin-secret")
        XCTAssertFalse(String(data: try JSONEncoder().encode(operation), encoding: .utf8)?.contains("new-admin-secret") == true)
    }

    func testRedisRelaySettingsUseRuntimeOwnerAPIWithoutReturningSecret() throws {
        let readClient = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: #"{"state":"loaded","settings":{"enabled":false,"target":{"url":"redis://redis.example:6379/0","username":"","passwordConfigured":true,"tls":false},"scope":"vital_reconstruction","includeRecorderNetworkContext":false,"intervalSeconds":1.0,"scanCount":1000},"readError":null}"#
        ))
        let readGateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330", httpClient: readClient
        )

        let read = try readGateway.redisRelaySettings()

        XCTAssertEqual(read.settings?.target.passwordConfigured, true)
        XCTAssertEqual(readClient.requests.map(\.httpMethod), ["GET"])
        XCTAssertFalse(String(data: try JSONEncoder().encode(read), encoding: .utf8)?.contains("password\":") == true)

        let applyClient = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 202,
            body: #"{"operationId":"relay-settings-1","service":"redis-relay-settings","command":"apply-redis-relay-settings","state":"completed","createdAt":"2026-07-01T00:00:00+00:00","updatedAt":"2026-07-01T00:00:01+00:00"}"#
        ))
        let applyGateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330", httpClient: applyClient
        )
        let request = RuntimeRedisRelaySettingsApplyRequest(
            enabled: true,
            target: RuntimeRedisRelayTargetApply(
                url: "redis://relay.example:6379/1",
                username: "relay",
                password: "relay-secret",
                clearPassword: false,
                tls: true
            ),
            scope: .waveformTrendOnly,
            includeRecorderNetworkContext: true,
            intervalSeconds: 0.5,
            scanCount: 250
        )

        let operation = try applyGateway.applyRedisRelaySettings(request)

        XCTAssertEqual(operation.command, .applyRedisRelaySettings)
        XCTAssertEqual(applyClient.requests.map(\.httpMethod), ["PUT"])
        XCTAssertEqual(
            applyClient.requests.first?.url?.absoluteString,
            "http://127.0.0.1:18330/runtime/redis-relay/settings"
        )
        XCTAssertFalse(String(data: try JSONEncoder().encode(operation), encoding: .utf8)?.contains("relay-secret") == true)
    }

    func testRuntimeEventsPreserveOpaqueGuestCursor() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "events": [{
                "schemaVersion": 1,
                "id": "runtime-operation-event-9",
                "source": "runtime-controller",
                "eventType": "operation-completed",
                "timestamp": "2026-07-01T00:00:01+00:00",
                "operationId": "runtime-settings-1",
                "operationService": "runtime-settings",
                "operationCommand": "apply-settings",
                "operationState": "completed",
                "message": "runtime-settings apply-settings completed",
                "failure": null
              }],
              "nextCursor": "event:9",
              "matchingCount": null
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let history = try gateway.runtimeEvents(query: RuntimeOperationEventQuery(
            limit: 20,
            eventType: .completed,
            since: "2026-07-01T09:00:00+09:00",
            cursor: "guest+ledger/token=v2"
        ))

        XCTAssertEqual(history.events.first?.operationCommand, "apply-settings")
        XCTAssertEqual(history.nextCursor, "event:9")
        XCTAssertEqual(
            client.requests.first?.url?.absoluteString,
            "http://127.0.0.1:18330/runtime/events?limit=20&type=operation-completed&since=2026-07-01T09%3A00%3A00%2B09%3A00&cursor=guest%2Bledger%2Ftoken%3Dv2"
        )
    }

    func testListServicesRequestsGuestControlServicesEndpoint() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: #"{"services":["app","recorder-ingress","postgres"]}"#
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let result = try gateway.listServices()

        XCTAssertEqual(result, RuntimeGuestControlServiceList(services: ["app", "recorder-ingress", "postgres"]))
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/runtime/services"])
    }

    func testServiceCommandsPostAndDecodeOperation() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 202,
            body: """
            {
              "operationId": "command-app-1",
              "service": "app",
              "command": "start",
              "state": "completed",
              "createdAt": "2026-07-01T00:00:00+00:00",
              "updatedAt": "2026-07-01T00:00:01+00:00"
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330/",
            httpClient: client
        )

        let operation = try gateway.startService("app")

        XCTAssertEqual(operation.operationId, "command-app-1")
        XCTAssertEqual(operation.service, "app")
        XCTAssertEqual(operation.command, .start)
        XCTAssertEqual(operation.state, .completed)
        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST"])
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/runtime/services/app/start"])
    }

    func testStackStatusRequestsGuestControlStackStatusEndpoint() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "state": "loaded",
              "observedAt": "2026-07-01T00:00:00+00:00",
              "services": [
                {
                  "service": "app",
                  "state": "running",
                  "health": "healthy",
                  "observedAt": "2026-07-01T00:00:00+00:00",
                  "container": "vitalserver-app-1",
                  "exitCode": 0
                },
                {
                  "service": "redis",
                  "state": "absent",
                  "health": "not_reported",
                  "observedAt": "2026-07-01T00:00:00+00:00"
                }
              ],
              "probeErrors": [
                {
                  "source": "docker stats",
                  "message": "timed out after 1 seconds"
                }
              ]
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let status = try gateway.stackStatus()

        XCTAssertEqual(status.state, "loaded")
        XCTAssertEqual(status.observedAt, "2026-07-01T00:00:00+00:00")
        XCTAssertEqual(status.services.map(\.service), ["app", "redis"])
        XCTAssertEqual(status.services.first?.container, "vitalserver-app-1")
        XCTAssertEqual(status.services.first?.exitCode, 0)
        XCTAssertEqual(status.services.last?.state, "absent")
        XCTAssertEqual(status.services.last?.health, "not_reported")
        XCTAssertEqual(status.probeErrors, [
            GuestRuntimeProbeError(
                source: "docker stats",
                message: "timed out after 1 seconds"
            )
        ])
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/runtime/stack"])
    }

    func testStopAndRestartServiceCommandsEncodeServiceAsOnePathSegment() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 202,
            body: """
            {
              "operationId": "command-service-1",
              "service": "recorder/ingress",
              "command": "stop",
              "state": "completed",
              "createdAt": "2026-07-01T00:00:00+00:00",
              "updatedAt": "2026-07-01T00:00:01+00:00"
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330/",
            httpClient: client
        )

        _ = try gateway.stopService("recorder/ingress")
        _ = try gateway.restartService("recorder/ingress")

        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST", "POST"])
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, [
            "http://127.0.0.1:18330/runtime/services/recorder%2Fingress/stop",
            "http://127.0.0.1:18330/runtime/services/recorder%2Fingress/restart",
        ])
    }

    func testReconcileServicesPostsStackReconcileEndpoint() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 202,
            body: """
            {
              "operationId": "reconcile-1",
              "service": "guest-stack",
              "command": "reconcile",
              "state": "completed",
              "createdAt": "2026-07-01T00:00:00+00:00",
              "updatedAt": "2026-07-01T00:00:01+00:00"
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330/",
            httpClient: client
        )

        let operation = try gateway.reconcileServices()

        XCTAssertEqual(operation.operationId, "reconcile-1")
        XCTAssertEqual(operation.service, "guest-stack")
        XCTAssertEqual(operation.command, .reconcile)
        XCTAssertEqual(operation.state, .completed)
        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST"])
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/runtime/stack/reconcile"])
    }

    func testRedisBackupPostsMaintenanceEndpointAndDecodesResult() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 202,
            body: """
            {
              "operationId": "redis-backup-1",
              "service": "redis-backup",
              "command": "redis-backup",
              "state": "completed",
              "createdAt": "2026-07-01T00:00:00+00:00",
              "updatedAt": "2026-07-01T00:00:01+00:00",
              "result": {
                "archive": "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
              }
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330/",
            httpClient: client
        )

        let operation = try gateway.createRedisBackup()

        XCTAssertEqual(operation.operationId, "redis-backup-1")
        XCTAssertEqual(operation.service, "redis-backup")
        XCTAssertEqual(operation.command, .redisBackup)
        XCTAssertEqual(operation.state, .completed)
        XCTAssertEqual(operation.result?.archive, "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz")
        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/maintenance/redis-backup"]
        )
    }

    func testRedisRestorePostsMaintenanceEndpointAndDecodesResult() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 202,
            body: """
            {
              "operationId": "redis-restore-1",
              "service": "redis-restore",
              "command": "redis-restore",
              "state": "completed",
              "createdAt": "2026-07-01T00:00:00+00:00",
              "updatedAt": "2026-07-01T00:00:01+00:00",
              "result": {
                "restoredArchive": "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
              }
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330/",
            httpClient: client
        )

        let operation = try gateway.restoreRedisBackup(
            archive: "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
        )

        XCTAssertEqual(operation.operationId, "redis-restore-1")
        XCTAssertEqual(operation.service, "redis-restore")
        XCTAssertEqual(operation.command, .redisRestore)
        XCTAssertEqual(operation.state, .completed)
        XCTAssertEqual(operation.result?.restoredArchive, "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz")
        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/maintenance/redis-restore"]
        )
        XCTAssertEqual(
            client.requests.first?.httpBody.flatMap { String(data: $0, encoding: .utf8) },
            #"{"archive":"\/mnt\/tirosh-runtime\/backups\/redis\/redis-20260701.tar.gz"}"#
        )
    }

    func testDatastoreRepairPostsMaintenanceEndpointAndDecodesOperation() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 202,
            body: """
            {
              "operationId": "datastore-repair-1",
              "service": "datastore-repair",
              "command": "repair-datastore",
              "state": "completed",
              "createdAt": "2026-07-01T00:00:00+00:00",
              "updatedAt": "2026-07-01T00:00:01+00:00"
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330/",
            httpClient: client
        )

        let operation = try gateway.repairDatastore()

        XCTAssertEqual(operation.operationId, "datastore-repair-1")
        XCTAssertEqual(operation.service, "datastore-repair")
        XCTAssertEqual(operation.command, .repairDatastore)
        XCTAssertEqual(operation.state, .completed)
        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/maintenance/datastore/repair"]
        )
    }

    func testUpdateActivationPostsMaintenanceEndpointAndDecodesResult() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 202,
            body: """
            {
              "operationId": "update-activation-1",
              "service": "update-activation",
              "command": "activate-update",
              "state": "completed",
              "createdAt": "2026-07-01T00:00:00+00:00",
              "updatedAt": "2026-07-01T00:00:01+00:00",
              "result": {
                "requestId": "update-activation-request-1",
                "version": "0.2.0"
              }
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330/",
            httpClient: client
        )

        let operation = try gateway.activateUpdate(
            requestId: "update-activation-request-1",
            version: "0.2.0"
        )

        XCTAssertEqual(operation.operationId, "update-activation-1")
        XCTAssertEqual(operation.service, "update-activation")
        XCTAssertEqual(operation.command, .updateActivation)
        XCTAssertEqual(operation.state, .completed)
        XCTAssertEqual(operation.result?.requestId, "update-activation-request-1")
        XCTAssertEqual(operation.result?.version, "0.2.0")
        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/maintenance/update-activation"]
        )
        let body = try XCTUnwrap(client.requests.first?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["requestId"] as? String, "update-activation-request-1")
        XCTAssertEqual(object["version"] as? String, "0.2.0")
    }

    func testServiceStatusDecodesExplicitContainerState() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "service": "app",
              "state": "running",
              "health": "healthy",
              "observedAt": "2026-07-01T00:00:00+00:00",
              "container": "vitalserver-app-1",
              "exitCode": 0
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let status = try gateway.serviceStatus("app")

        XCTAssertEqual(status.service, "app")
        XCTAssertEqual(status.state, "running")
        XCTAssertEqual(status.health, "healthy")
        XCTAssertEqual(status.container, "vitalserver-app-1")
        XCTAssertEqual(status.exitCode, 0)
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/runtime/services/app/status"])
    }

    func testServiceResourceDecodesControllerResource() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "service": "app",
              "spec": {
                "state": "configured",
                "desiredState": "running",
                "updatedAt": "2026-07-01T00:00:00+00:00"
              },
              "status": {
                "state": "loaded",
                "observedState": "running",
                "observedAt": "2026-07-01T00:00:01+00:00",
                "serviceStatus": {
                  "service": "app",
                  "state": "running",
                  "health": "healthy",
                  "observedAt": "2026-07-01T00:00:01+00:00"
                },
                "readError": null
              },
              "conditions": [
                {
                  "type": "Reconciled",
                  "status": "true",
                  "reason": "DesiredStateObserved",
                  "message": "Guest service already matches desired running state.",
                  "observedAt": "2026-07-01T00:00:02+00:00"
                }
              ],
              "lastOperationId": "op_app_reconcile_1"
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let resource = try gateway.serviceResource("app")

        XCTAssertEqual(resource.service, "app")
        XCTAssertEqual(resource.spec.desiredState, "running")
        XCTAssertEqual(resource.status.observedState, "running")
        XCTAssertEqual(resource.conditions.first?.reason, "DesiredStateObserved")
        XCTAssertEqual(resource.lastOperationId, "op_app_reconcile_1")
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/runtime/services/app/resource"])
    }

    func testHTTPErrorPreservesGuestControlErrorDocument() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 404,
            body: """
            {
              "detail": "compose service is not available: missing",
              "code": "serviceNotFound",
              "availableServices": ["app", "redis"]
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        XCTAssertThrowsError(try gateway.restartService("missing")) { error in
            XCTAssertEqual(
                error as? RuntimeGuestControlHTTPGatewayError,
                .requestFailed(
                    statusCode: 404,
                    code: "serviceNotFound",
                    detail: "compose service is not available: missing",
                    availableServices: ["app", "redis"]
                )
            )
        }
    }

    func testRuntimeEventsMapsGuestQueryRejectionToApplicationBoundaryError() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 400,
            body: """
            {
              "detail": "runtime event history cursor is invalid",
              "code": "queryParameterInvalid"
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        XCTAssertThrowsError(
            try gateway.runtimeEvents(
                query: RuntimeOperationEventQuery(cursor: "guest-ledger-token")
            )
        ) { error in
            XCTAssertEqual(
                error as? RuntimeGuestOperationEventQueryRejectedError,
                RuntimeGuestOperationEventQueryRejectedError(
                    detail: "runtime event history cursor is invalid"
                )
            )
        }
    }

    func testRuntimeEventsMapsGuestLedgerUnavailableToApplicationBoundaryError() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 503,
            body: """
            {
              "detail": "Guest operation event ledger is unavailable",
              "code": "controlStoreUnavailable"
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        XCTAssertThrowsError(
            try gateway.runtimeEvents(query: RuntimeOperationEventQuery())
        ) { error in
            XCTAssertEqual(
                error as? RuntimeGuestOperationEventHistoryUnavailableError,
                RuntimeGuestOperationEventHistoryUnavailableError(
                    detail: "Guest operation event ledger is unavailable"
                )
            )
        }
    }

    func testHTTPConflictMapsToPublicOperationInProgressMeaning() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 409,
            body: """
            {
              "detail": "guest control lease is held by operation op-123",
              "code": "operationInProgress"
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        XCTAssertThrowsError(try gateway.startService("app")) { error in
            XCTAssertEqual(
                error as? RuntimeControlOperationInProgressError,
                RuntimeControlOperationInProgressError(
                    message: "guest control lease is held by operation op-123"
                )
            )
            XCTAssertEqual(
                error.localizedDescription,
                "guest control lease is held by operation op-123"
            )
        }
    }

    func testLatestVitalDBObservationRequestsGuestControlReadModelEndpoint() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "state": "loaded",
              "observation": {
                "schemaVersion": 1,
                "source": "vitaldb-observer",
                "observedAt": "2026-07-01T00:00:00+00:00",
                "ready": true,
                "recorderOnlineThresholdSeconds": 60,
                "recorders": [],
                "beds": [],
                "devices": [],
                "filters": [],
                "proxyConnections": [],
                "anomalies": [],
                "readIssues": []
              },
              "readError": null
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let read = try gateway.latestVitalDBObservation()

        XCTAssertEqual(read.state, .loaded)
        XCTAssertEqual(read.observation?.observedAt, "2026-07-01T00:00:00+00:00")
        XCTAssertEqual(read.readError, nil)
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/vitaldb/observations/latest"]
        )
    }

    func testVitalDBRecordersRequestsGuestControlReadModelEndpoint() throws {
        let responseDocument = RuntimeVitalRecorderHistory(
            updatedAt: "2026-07-01T00:00:00+00:00",
            recorders: [
                RuntimeVitalRecorderRecord(
                    vrcode: "VR-001",
                    status: .online,
                    lastIP: "10.0.0.10",
                    version: nil,
                    bedID: nil,
                    bedName: nil,
                    patientConnected: nil,
                    firstSeenAt: "2026-07-01T00:00:00+00:00",
                    lastSeenAt: "2026-07-01T00:00:00+00:00",
                    observationCount: 1,
                    currentAnomalyCount: 0,
                    latestAnomalySeverity: nil
                ),
            ]
        )
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: String(decoding: try JSONEncoder().encode(responseDocument), as: UTF8.self)
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let read = try gateway.vitalDBRecorders()

        XCTAssertEqual(read.state, .loaded)
        XCTAssertEqual(read.updatedAt, "2026-07-01T00:00:00+00:00")
        XCTAssertEqual(read.recorders.map(\.vrcode), ["VR-001"])
        XCTAssertEqual(read.readError, nil)
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/vitaldb/recorders"]
        )
    }

    func testVitalDBRecorderVisibilityCommandsPostGuestControlReadModelRequests() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: String(decoding: try JSONEncoder().encode(RuntimeVitalRecorderHistory()), as: UTF8.self)
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        _ = try gateway.hideVitalDBRecorders(.init(vrcodes: ["VR-001"]))
        _ = try gateway.unhideVitalDBRecorders(.init(vrcodes: ["VR-001"]))
        _ = try gateway.deleteVitalDBRecorders(.init(vrcodes: ["VR-001"]))

        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST", "POST", "POST"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            [
                "http://127.0.0.1:18330/runtime/vitaldb/recorders/hide",
                "http://127.0.0.1:18330/runtime/vitaldb/recorders/unhide",
                "http://127.0.0.1:18330/runtime/vitaldb/recorders/delete",
            ]
        )
        for request in client.requests {
            let body = try XCTUnwrap(request.httpBody)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(object["vrcodes"] as? [String], ["VR-001"])
        }
    }

    func testVitalDBRecorderActivityRequestsGuestControlReadModelEndpoint() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "state": "loaded",
              "vrcode": "VR-001",
              "buckets": [
                {
                  "vrcode": "VR-001",
                  "bucketStartedAt": "2026-07-01T00:00:00+00:00",
                  "bucketSeconds": 60,
                  "messageCount": 2,
                  "byteCount": 128,
                  "roomCount": 1,
                  "firstObservedAt": "2026-07-01T00:00:00+00:00",
                  "lastObservedAt": "2026-07-01T00:00:59+00:00"
                }
              ],
              "readError": null
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let read = try gateway.vitalDBRecorderActivity("VR-001")

        XCTAssertEqual(read.state, .loaded)
        XCTAssertEqual(read.vrcode, "VR-001")
        XCTAssertEqual(read.buckets.map(\.messageCount), [2])
        XCTAssertEqual(read.buckets.map(\.byteCount), [128])
        XCTAssertEqual(read.readError, nil)
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/vitaldb/recorders/VR-001/activity"]
        )
    }

    func testVitalDBBedsRequestsGuestControlReadModelEndpoint() throws {
        let responseDocument = RuntimeVitalBedHistory(
            updatedAt: "2026-07-01T00:00:00+00:00",
            beds: [
                RuntimeVitalBedRecord(
                    bedID: "bed-a",
                    name: "OR-A",
                    vrcode: "VR-001",
                    status: .online,
                    patientConnected: nil,
                    firstSeenAt: "2026-07-01T00:00:00+00:00",
                    lastSeenAt: "2026-07-01T00:00:00+00:00",
                    observationCount: 1,
                    currentAnomalyCount: 0,
                    latestAnomalySeverity: nil
                ),
            ]
        )
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: String(decoding: try JSONEncoder().encode(responseDocument), as: UTF8.self)
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let read = try gateway.vitalDBBeds()

        XCTAssertEqual(read.state, .loaded)
        XCTAssertEqual(read.updatedAt, "2026-07-01T00:00:00+00:00")
        XCTAssertEqual(read.beds.map(\.bedID), ["bed-a"])
        XCTAssertEqual(read.readError, nil)
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/vitaldb/beds"]
        )
    }

    func testVitalDBBedVisibilityCommandsPostGuestControlReadModelRequests() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: String(decoding: try JSONEncoder().encode(RuntimeVitalBedHistory()), as: UTF8.self)
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        _ = try gateway.hideVitalDBBeds(.init(bedIDs: ["bed-a"]))
        _ = try gateway.unhideVitalDBBeds(.init(bedIDs: ["bed-a"]))
        _ = try gateway.deleteVitalDBBeds(.init(bedIDs: ["bed-a"]))

        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST", "POST", "POST"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            [
                "http://127.0.0.1:18330/runtime/vitaldb/beds/hide",
                "http://127.0.0.1:18330/runtime/vitaldb/beds/unhide",
                "http://127.0.0.1:18330/runtime/vitaldb/beds/delete",
            ]
        )
        for request in client.requests {
            let body = try XCTUnwrap(request.httpBody)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(object["bedIDs"] as? [String], ["bed-a"])
        }
    }

    func testVitalDBRelationshipsRequestsGuestControlReadModelEndpoint() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "state": "loaded",
              "assignments": [
                {
                  "assignmentID": "assignment-1",
                  "bedID": "bed-a",
                  "bedName": "OR-A",
                  "vrcode": "VR-001",
                  "startedAt": "2026-07-01T00:00:00+00:00",
                  "endedAt": null,
                  "lastSeenAt": "2026-07-01T00:00:05+00:00",
                  "lastObservedAt": "2026-07-01T00:00:05+00:00",
                  "status": "online",
                  "patientConnected": true,
                  "observationCount": 2
                }
              ],
              "events": [],
              "readError": null
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let read = try gateway.vitalDBRelationships()

        XCTAssertEqual(read.state, .loaded)
        XCTAssertEqual(read.assignments.map(\.assignmentID), ["assignment-1"])
        XCTAssertEqual(read.events, [])
        XCTAssertEqual(read.readError, nil)
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/vitaldb/relationships"]
        )
    }

    func testLabScenariosDecodeRuntimeLabContract() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "state": "loaded",
              "scenarios": [
                {
                  "scenarioId": "normal_monitoring",
                  "name": "Normal monitoring",
                  "category": "virtual-recorder",
                  "description": "Stable monitoring"
                }
              ],
              "readError": null
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let scenarios = try gateway.labScenarios()

        XCTAssertEqual(scenarios.state, .loaded)
        XCTAssertEqual(scenarios.scenarios.map(\.scenarioId), ["normal_monitoring"])
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/runtime/lab/scenarios"])
    }

    func testLabVitalFilesDecodeRuntimeLabCatalog() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "state": "loaded",
              "vitalFiles": [
                {
                  "displayName": "sample.vital",
                  "relativePath": "MORA04/sample.vital",
                  "guestPath": "/mnt/tirosh-vital-files/MORA04/sample.vital",
                  "sizeBytes": 123,
                  "modifiedAt": "2026-07-01T00:00:00Z"
                }
              ],
              "readError": null
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let catalog = try gateway.labVitalFiles()

        XCTAssertEqual(catalog.state, .loaded)
        XCTAssertEqual(catalog.vitalFiles.map(\.relativePath), ["MORA04/sample.vital"])
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/runtime/lab/vital-files"])
    }

    func testLabBedsAndRecordersDecodeRuntimeLabReadModels() throws {
        let bedsClient = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "state": "loaded",
              "beds": [
                {
                  "bedId": "lab-session-1-bed-1",
                  "sessionId": "lab-session-1",
                  "name": "OR-A",
                  "state": "running",
                  "createdAt": "2026-07-01T00:00:00+00:00",
                  "updatedAt": "2026-07-01T00:00:01+00:00"
                }
              ],
              "readError": null
            }
            """
        ))
        let recorderClient = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "state": "loaded",
              "recorders": [
                {
                  "recorderId": "lab-session-1-recorder-1",
                  "sessionId": "lab-session-1",
                  "bedId": "lab-session-1-bed-1",
                  "vrcode": "LAB-lab-session-1-1",
                  "state": "running",
                  "createdAt": "2026-07-01T00:00:00+00:00",
                  "updatedAt": "2026-07-01T00:00:01+00:00",
                  "messagesSent": 1,
                  "lastSendState": "sent",
                  "lastSendAt": "2026-07-01T00:00:01+00:00",
                  "lastSendError": null
                }
              ],
              "readError": null
            }
            """
        ))
        let bedsGateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: bedsClient
        )
        let recordersGateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: recorderClient
        )

        let beds = try bedsGateway.labBeds()
        let recorders = try recordersGateway.labRecorders()

        XCTAssertEqual(beds.state, .loaded)
        XCTAssertEqual(beds.beds.first?.name, "OR-A")
        XCTAssertEqual(bedsClient.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/runtime/lab/beds"])
        XCTAssertEqual(recorders.state, .loaded)
        XCTAssertEqual(recorders.recorders.first?.vrcode, "LAB-lab-session-1-1")
        XCTAssertEqual(recorders.recorders.first?.messagesSent, 1)
        XCTAssertEqual(recorders.recorders.first?.lastSendState, .sent)
        XCTAssertEqual(recorders.recorders.first?.lastSendError, nil)
        XCTAssertEqual(
            recorderClient.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/lab/recorders"]
        )
    }

    func testCreateLabSessionPostsRuntimeLabRequest() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 202,
            body: labSessionResponseBody(operationId: "op_lab_1")
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let response = try gateway.createLabSession(RuntimeLabSessionCreateRequest(
            scenarioId: "normal_monitoring",
            name: "Recovery",
            recorderCount: 2,
            targetURL: "http://edge/"
        ))

        XCTAssertEqual(response.state, .loaded)
        XCTAssertEqual(response.operationId, "op_lab_1")
        XCTAssertEqual(response.labOperationId, "lab_op_lab_1")
        XCTAssertEqual(response.session?.sessionId, "lab-session-1")
        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST"])
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/runtime/lab/sessions"])
        let body = try XCTUnwrap(client.requests.first?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["scenarioId"] as? String, "normal_monitoring")
        XCTAssertEqual(object["name"] as? String, "Recovery")
        XCTAssertEqual(object["recorderCount"] as? Int, 2)
        XCTAssertEqual(object["targetURL"] as? String, "http://edge/")
    }

    func testLabSessionsReadsExplicitSessionCollection() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "state": "loaded",
              "sessions": [\(labSessionObjectBody())],
              "readError": null
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let response = try gateway.labSessions()

        XCTAssertEqual(response.state, .loaded)
        XCTAssertEqual(response.sessions.first?.sessionId, "lab-session-1")
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/lab/sessions"]
        )
    }

    func testLabSessionCommandsEncodeSessionIDAsOnePathSegment() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 202,
            body: labSessionResponseBody(operationId: "op_lab_2")
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        _ = try gateway.startLabSession("session/with space")

        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/lab/sessions/session%2Fwith%20space/start"]
        )
    }

    func testLabRecorderCommandEncodesSessionAndRecorderAsPathSegments() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 202,
            body: labRecorderResponseBody(operationId: "op_recorder_1")
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let response = try gateway.stopLabRecorder(
            sessionId: "session/with space",
            recorderId: "recorder/with space"
        )

        XCTAssertEqual(response.recorder?.state, .stopped)
        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            [
                "http://127.0.0.1:18330/runtime/lab/sessions/session%2Fwith%20space/recorders/recorder%2Fwith%20space/stop"
            ]
        )
    }

    func testRecorderIngressStatusRequestsGuestControlStatusEndpoint() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "readState": "loaded",
              "httpStatus": "200",
              "document": {
                "activeWebSockets": 1,
                "activeRecorderConnections": 1,
                "httpRequests": 0,
                "socketIoEventsSeen": 0,
                "socketIoParseFailures": 0,
                "auditWriteFailures": 0,
                "auditFileWriteFailures": 0,
                "auditStdoutWriteFailures": 0,
                "failureLogWriteFailures": 0,
                "redisIpWriteFailures": 0,
                "redisIpVerifyFailures": 0,
                "redisIpVerifyMismatches": 0,
                "recorders": [
                  {
                    "vrcode": "VR_GUEST",
                    "activeConnections": 1,
                    "selectedIp": "192.168.64.24",
                    "lastSeenAt": "2026-07-01T00:00:00+00:00"
                  }
                ]
              },
              "readError": null
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let read = try gateway.recorderIngressStatus()

        XCTAssertEqual(read.readState, .loaded)
        XCTAssertEqual(read.document?.recorders.map(\.vrcode), ["VR_GUEST"])
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/recorder-ingress/status"]
        )
    }

    func testRedisRelayStatusRequestsGuestControlStatusEndpoint() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "readState": "loaded",
              "document": {
                "schemaVersion": 1,
                "observedAt": "2026-07-01T00:00:00Z",
                "enabled": true,
                "state": "running",
                "scope": "vital_reconstruction",
                "targetUrl": "redis://relay.example:6379/0",
                "targetUsernameConfigured": true,
                "targetPasswordConfigured": true,
                "settingsFingerprint": "relay-settings",
                "batches": 3,
                "totals": {
                  "scanned": 10,
                  "copied": 8,
                  "published": 8,
                  "unchanged": 1,
                  "duplicates": 0,
                  "skipped": 1,
                  "denied": 0,
                  "missing": 0,
                  "errors": 0
                },
                "lastBatch": null,
                "lastSuccessAt": null,
                "lastErrorAt": null,
                "lastError": null
              },
              "readError": null
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let read = try gateway.redisRelayStatus()

        XCTAssertEqual(read.readState, .loaded)
        XCTAssertEqual(read.document?.state, "running")
        XCTAssertEqual(read.document?.totals.copied, 8)
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/redis-relay/status"]
        )
    }

    func testReplayLabVitalFilePostsRuntimeLabRequest() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 202,
            body: labSessionResponseBody(operationId: "op_replay_1")
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let response = try gateway.replayLabVitalFile(RuntimeLabVitalFileReplayRequest(
            vitalFileRelativePath: "sample.vital",
            sessionName: "Replay",
            targetURL: "http://edge/",
            resourceSelection: RuntimeLabVitalFileReplayResourceSelection(mode: .quickCreate),
            repeatPolicy: RuntimeLabVitalFileReplayPolicy(mode: .once)
        ))

        XCTAssertEqual(response.operationId, "op_replay_1")
        XCTAssertEqual(response.labOperationId, "lab_op_replay_1")
        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/runtime/lab/vital-files/replay"]
        )
        let body = try XCTUnwrap(client.requests.first?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["vitalFileRelativePath"] as? String, "sample.vital")
        XCTAssertEqual(object["sessionName"] as? String, "Replay")
        XCTAssertEqual(object["targetURL"] as? String, "http://edge/")
    }

    func testUploadLabVitalFilesForwardsMultipartBytesToGuestController() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "state": "completed",
              "files": [
                {
                  "fileName": "OR-A_260715_120000.vital",
                  "relativePath": "OR-A/202607/260715/OR-A_260715_120000.vital",
                  "sizeBytes": 5
                }
              ]
            }
            """
        ))
        let gateway = try HTTPRuntimeGuestControlGateway(
            baseURL: "http://127.0.0.1:18330",
            httpClient: client
        )

        let result = try gateway.uploadLabVitalFiles([
            RuntimeLabVitalFileUploadSource(
                fileName: "OR-A_260715_120000.vital",
                content: Data("vital".utf8)
            )
        ])

        XCTAssertEqual(result.files.first?.relativePath, "OR-A/202607/260715/OR-A_260715_120000.vital")
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "http://127.0.0.1:18330/runtime/lab/vital-files/upload"
        )
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertNotNil(body.range(of: Data("name=\"files\"".utf8)))
        XCTAssertNotNil(body.range(of: Data("OR-A_260715_120000.vital".utf8)))
        XCTAssertNotNil(body.range(of: Data("vital".utf8)))
    }

}

private final class CapturingRuntimeGuestControlHTTPClient: RuntimeGuestControlHTTPClient, @unchecked Sendable {
    private let response: RuntimeGuestControlHTTPResponse
    private let lock = NSLock()
    private var capturedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    init(response: RuntimeGuestControlHTTPResponse) {
        self.response = response
    }

    func send(_ request: URLRequest) throws -> RuntimeGuestControlHTTPResponse {
        lock.lock()
        capturedRequests.append(request)
        lock.unlock()
        return response
    }
}

private func jsonResponse(statusCode: Int, body: String) -> RuntimeGuestControlHTTPResponse {
    RuntimeGuestControlHTTPResponse(
        statusCode: statusCode,
        data: Data(body.utf8)
    )
}

private func labSessionResponseBody(operationId: String) -> String {
    """
    {
      "state": "loaded",
      "session": {
        "sessionId": "lab-session-1",
        "state": "running",
        "scenarioId": "normal_monitoring",
        "name": "Recovery",
        "recorderCount": 2,
        "targetURL": "http://edge/",
        "createdAt": "2026-07-01T00:00:00+00:00",
        "updatedAt": "2026-07-01T00:00:01+00:00"
      },
      "operationId": "\(operationId)",
      "labOperationId": "lab_\(operationId)",
      "readError": null
    }
    """
}

private func labSessionObjectBody() -> String {
    """
    {
      "sessionId": "lab-session-1",
      "state": "running",
      "scenarioId": "normal_monitoring",
      "name": "Recovery",
      "recorderCount": 2,
      "targetURL": "http://edge/",
      "createdAt": "2026-07-01T00:00:00+00:00",
      "updatedAt": "2026-07-01T00:00:01+00:00"
    }
    """
}

private func labRecorderResponseBody(operationId: String) -> String {
    """
    {
      "state": "loaded",
      "recorder": {
        "recorderId": "lab-session-1-recorder-1",
        "sessionId": "lab-session-1",
        "bedId": "lab-session-1-bed-1",
        "vrcode": "LAB-REC001",
        "state": "stopped",
        "messagesSent": 1,
        "lastSendState": "sent"
      },
      "operationId": "\(operationId)",
      "labOperationId": "lab_\(operationId)",
      "readError": null
    }
    """
}
