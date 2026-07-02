import Contracts
import Foundation
import OutboundAdapters
import RuntimeControl
import XCTest

final class HTTPRuntimeGuestControlGatewayTests: XCTestCase {
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
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/v1/capabilities"])
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
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/v1/services"])
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
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/v1/services/app/start"])
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
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/v1/stack/status"])
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
            "http://127.0.0.1:18330/v1/services/recorder%2Fingress/stop",
            "http://127.0.0.1:18330/v1/services/recorder%2Fingress/restart",
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
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/v1/stack/reconcile"])
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
            ["http://127.0.0.1:18330/v1/maintenance/redis-backup"]
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
            ["http://127.0.0.1:18330/v1/maintenance/redis-restore"]
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
            ["http://127.0.0.1:18330/v1/maintenance/datastore-repair"]
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
            ["http://127.0.0.1:18330/v1/maintenance/update-activation"]
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
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/v1/services/app/status"])
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
            ["http://127.0.0.1:18330/v1/vitaldb/observations/latest"]
        )
    }

    func testVitalDBRecordersRequestsGuestControlReadModelEndpoint() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "state": "loaded",
              "observedAt": "2026-07-01T00:00:00+00:00",
              "ready": true,
              "recorderOnlineThresholdSeconds": 60,
              "recorders": [
                {
                  "vrcode": "VR-001",
                  "ip": "10.0.0.10",
                  "online": true,
                  "stale": false
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

        let read = try gateway.vitalDBRecorders()

        XCTAssertEqual(read.state, .loaded)
        XCTAssertEqual(read.observedAt, "2026-07-01T00:00:00+00:00")
        XCTAssertEqual(read.ready, true)
        XCTAssertEqual(read.recorderOnlineThresholdSeconds, 60)
        XCTAssertEqual(read.recorders.map(\.vrcode), ["VR-001"])
        XCTAssertEqual(read.readError, nil)
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/v1/vitaldb/recorders"]
        )
    }

    func testVitalDBRecorderVisibilityCommandsPostGuestControlReadModelRequests() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "state": "loaded",
              "observedAt": "2026-07-01T00:00:00+00:00",
              "ready": true,
              "recorderOnlineThresholdSeconds": 60,
              "recorders": [],
              "readError": null
            }
            """
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
                "http://127.0.0.1:18330/v1/vitaldb/recorders/hide",
                "http://127.0.0.1:18330/v1/vitaldb/recorders/unhide",
                "http://127.0.0.1:18330/v1/vitaldb/recorders/delete",
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
            ["http://127.0.0.1:18330/v1/vitaldb/recorders/VR-001/activity"]
        )
    }

    func testVitalDBBedsRequestsGuestControlReadModelEndpoint() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "state": "loaded",
              "observedAt": "2026-07-01T00:00:00+00:00",
              "ready": true,
              "recorderOnlineThresholdSeconds": 60,
              "beds": [
                {
                  "bedID": "bed-a",
                  "name": "OR-A",
                  "vrcode": "VR-001",
                  "online": true
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

        let read = try gateway.vitalDBBeds()

        XCTAssertEqual(read.state, .loaded)
        XCTAssertEqual(read.observedAt, "2026-07-01T00:00:00+00:00")
        XCTAssertEqual(read.ready, true)
        XCTAssertEqual(read.recorderOnlineThresholdSeconds, 60)
        XCTAssertEqual(read.beds.map(\.bedID), ["bed-a"])
        XCTAssertEqual(read.readError, nil)
        XCTAssertEqual(client.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/v1/vitaldb/beds"]
        )
    }

    func testVitalDBBedVisibilityCommandsPostGuestControlReadModelRequests() throws {
        let client = CapturingRuntimeGuestControlHTTPClient(response: jsonResponse(
            statusCode: 200,
            body: """
            {
              "state": "loaded",
              "observedAt": "2026-07-01T00:00:00+00:00",
              "ready": true,
              "recorderOnlineThresholdSeconds": 60,
              "beds": [],
              "readError": null
            }
            """
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
                "http://127.0.0.1:18330/v1/vitaldb/beds/hide",
                "http://127.0.0.1:18330/v1/vitaldb/beds/unhide",
                "http://127.0.0.1:18330/v1/vitaldb/beds/delete",
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
            ["http://127.0.0.1:18330/v1/vitaldb/relationships"]
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
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/v1/lab/scenarios"])
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
        XCTAssertEqual(bedsClient.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/v1/lab/beds"])
        XCTAssertEqual(recorders.state, .loaded)
        XCTAssertEqual(recorders.recorders.first?.vrcode, "LAB-lab-session-1-1")
        XCTAssertEqual(recorders.recorders.first?.messagesSent, 1)
        XCTAssertEqual(recorders.recorders.first?.lastSendState, .sent)
        XCTAssertEqual(recorders.recorders.first?.lastSendError, nil)
        XCTAssertEqual(
            recorderClient.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/v1/lab/recorders"]
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
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, ["http://127.0.0.1:18330/v1/lab/sessions"])
        let body = try XCTUnwrap(client.requests.first?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["scenarioId"] as? String, "normal_monitoring")
        XCTAssertEqual(object["name"] as? String, "Recovery")
        XCTAssertEqual(object["recorderCount"] as? Int, 2)
        XCTAssertEqual(object["targetURL"] as? String, "http://edge/")
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
            ["http://127.0.0.1:18330/v1/lab/sessions/session%2Fwith%20space/start"]
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
                "activeRecorderConnections": 1,
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
            ["http://127.0.0.1:18330/v1/recorder-ingress/status"]
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
            vitalFilePath: "/mnt/tirosh-vital-files/sample.vital",
            sessionName: "Replay",
            targetURL: "http://edge/"
        ))

        XCTAssertEqual(response.operationId, "op_replay_1")
        XCTAssertEqual(response.labOperationId, "lab_op_replay_1")
        XCTAssertEqual(client.requests.map(\.httpMethod), ["POST"])
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            ["http://127.0.0.1:18330/v1/lab/vital-files/replay"]
        )
        let body = try XCTUnwrap(client.requests.first?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["vitalFilePath"] as? String, "/mnt/tirosh-vital-files/sample.vital")
        XCTAssertEqual(object["sessionName"] as? String, "Replay")
        XCTAssertEqual(object["targetURL"] as? String, "http://edge/")
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
