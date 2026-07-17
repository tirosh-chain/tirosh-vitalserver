import type { Server as HttpServer } from "node:http";

import { Server as SocketIoServer } from "socket.io";

import type { RecorderGatewayIdentifierGenerator } from "../../recordergatewayapplication/recorder-gateway-ingress-and-cold-path-application-ports.js";
import type { RecorderGatewayIngressAndColdPathApplicationService } from "../../recordergatewayapplication/recorder-gateway-ingress-and-cold-path-application-service.js";
import { isRecorderGatewayIdentifier, recorderGatewaySchemaVersion, type RecorderIngressAcknowledgement, type RecorderGatewayConnection } from "../../recordergatewaydomain/recorder-gateway-ingress-and-cold-path-contracts.js";

interface JoinedRecorder {
  recorderId: string;
  connection: RecorderGatewayConnection;
  coldPathCaptureId: string;
}

// Socket.IO is an adapter boundary. It creates a transport-scoped connection
// and explicitly opens its Gateway-owned cold-path capture on join_vr; it does
// not infer Recorder health, upstream connectivity, Lab lifecycle, or archive
// success from the socket state.
export function attachRecorderGatewaySocketIoIngress(
  server: HttpServer,
  service: RecorderGatewayIngressAndColdPathApplicationService,
  identifiers: RecorderGatewayIdentifierGenerator,
): SocketIoServer {
  const socketServer = new SocketIoServer(server, {
    allowEIO3: true,
    transports: ["websocket", "polling"],
    maxHttpBufferSize: 4 * 1024 * 1024,
  });
  socketServer.on("connection", (socket) => {
    let joined: JoinedRecorder | undefined;

    socket.on("join_vr", (recorderCode: unknown, acknowledgement: unknown) => {
      if (joined !== undefined) {
        acknowledgeRecorderIngress(
          acknowledgement,
          rejectedRecorderIngress("recorder-session-already-joined", "one Socket.IO connection may own only one explicit Recorder cold-path capture"),
        );
        return;
      }
      void openSocketIoRecorderColdPathCapture(service, identifiers, recorderCode, acknowledgement, (nextJoined) => {
        joined = nextJoined;
      });
    });

    socket.on("send_data", (payload: unknown, acknowledgement: unknown) => {
      void admitSocketIoRecorderPacket(service, joined, payload, acknowledgement);
    });

    socket.on("req_cmd", (_request: unknown, acknowledgement: unknown) => {
      acknowledgeRecorderIngress(acknowledgement, {
        schemaVersion: recorderGatewaySchemaVersion,
        state: "unsupported",
        issue: {
          code: "recorder-command-dispatch-not-enabled",
          message: "Recorder command dispatch is outside the Recorder Gateway scope",
          retryable: false,
          dependency: "recorder-gateway",
        },
      });
    });
  });
  return socketServer;
}

async function openSocketIoRecorderColdPathCapture(
  service: RecorderGatewayIngressAndColdPathApplicationService,
  identifiers: RecorderGatewayIdentifierGenerator,
  recorderCode: unknown,
  acknowledgement: unknown,
  acceptJoinedRecorder: (joined: JoinedRecorder) => void,
): Promise<void> {
  if (typeof recorderCode !== "string" || !isRecorderGatewayIdentifier(recorderCode)) {
    acknowledgeRecorderIngress(acknowledgement, rejectedRecorderIngress("invalid-recorder-code", "join_vr requires a valid Recorder code"));
    return;
  }
  const recorderId = `recorder-${recorderCode}`;
  if (!isRecorderGatewayIdentifier(recorderId)) {
    acknowledgeRecorderIngress(acknowledgement, rejectedRecorderIngress("invalid-recorder-code", "Recorder code is too long for the v1 identifier contract"));
    return;
  }
  const connection: RecorderGatewayConnection = {
    sessionId: identifiers.newRecorderGatewayIdentifier("socket-session"),
    protocolVersion: "v2",
  };
  const captureOpen = await service.openRecorderColdPathCapture({ recorderId, connection });
  if (captureOpen.state !== "opened" || captureOpen.capture === undefined) {
    acknowledgeRecorderIngress(acknowledgement, {
      schemaVersion: recorderGatewaySchemaVersion,
      state: captureOpen.state === "rejected" ? "rejected" : "failed",
      issue: captureOpen.issue ?? {
        code: "recorder-cold-path-capture-open-result-invalid",
        message: "Recorder Gateway did not return a complete cold-path capture open result",
        retryable: true,
        dependency: "recorder-gateway",
      },
    });
    return;
  }
  const joined: JoinedRecorder = {
    recorderId,
    connection,
    coldPathCaptureId: captureOpen.capture.id,
  };
  acceptJoinedRecorder(joined);
  acknowledgeRecorderIngress(acknowledgement, {
    schemaVersion: recorderGatewaySchemaVersion,
    state: "accepted",
    sessionId: connection.sessionId,
    coldPathCaptureId: captureOpen.capture.id,
  });
}

async function admitSocketIoRecorderPacket(
  service: RecorderGatewayIngressAndColdPathApplicationService,
  joined: JoinedRecorder | undefined,
  payload: unknown,
  acknowledgement: unknown,
): Promise<void> {
  if (joined === undefined) {
    acknowledgeRecorderIngress(acknowledgement, rejectedRecorderIngress("recorder-session-not-joined", "send_data requires a prior accepted join_vr on this socket session"));
    return;
  }
  const normalized = normalizeSocketIoRecorderPacketPayload(payload);
  if (normalized === undefined) {
    acknowledgeRecorderIngress(acknowledgement, rejectedRecorderIngress("unsupported-send-data-payload", "send_data payload must be a binary string or binary attachment"));
    return;
  }
  const admission = await service.admitRecorderPacket({
    recorderId: joined.recorderId,
    connection: joined.connection,
    coldPathCaptureId: joined.coldPathCaptureId,
    payload: normalized.payload,
    payloadEncoding: normalized.encoding,
  });
  acknowledgeRecorderIngress(acknowledgement, admission.acknowledgement);
}

function normalizeSocketIoRecorderPacketPayload(payload: unknown): { payload: Uint8Array; encoding: "binary" | "binary-string" } | undefined {
  if (typeof payload === "string") {
    return { payload: Buffer.from(payload, "binary"), encoding: "binary-string" };
  }
  if (Buffer.isBuffer(payload)) {
    return { payload, encoding: "binary" };
  }
  if (payload instanceof Uint8Array) {
    return { payload: Buffer.from(payload), encoding: "binary" };
  }
  return undefined;
}

function acknowledgeRecorderIngress(candidate: unknown, payload: RecorderIngressAcknowledgement): void {
  if (typeof candidate === "function") {
    (candidate as (response: RecorderIngressAcknowledgement) => void)(payload);
  }
}

function rejectedRecorderIngress(code: string, message: string): RecorderIngressAcknowledgement {
  return {
    schemaVersion: recorderGatewaySchemaVersion,
    state: "rejected",
    issue: {
      code,
      message,
      retryable: false,
      dependency: "recorder-gateway",
    },
  };
}
