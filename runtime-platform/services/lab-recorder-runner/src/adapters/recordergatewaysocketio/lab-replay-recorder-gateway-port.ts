import { deflateSync } from "node:zlib";

import { io, type Socket } from "socket.io-client";

import type {
  LabReplayGatewayFrameAdmission,
  LabReplayGatewayPort,
} from "../../labrecorderrunnerapplication/lab-recorder-runner-ports.js";
import type { LabRecorderRunnerIssue } from "../../labrecorderrunnerdomain/lab-recorder-run-contracts.js";
import type {
  LabReplayFrame,
  LabReplayFrameTrack,
} from "../../labrecorderrunnerdomain/lab-replay-contracts.js";

interface GatewayAcknowledgement {
  schemaVersion?: unknown;
  state?: unknown;
  receiptId?: unknown;
  coldPathCaptureId?: unknown;
  issue?: {
    code?: unknown;
    message?: unknown;
    retryable?: unknown;
    dependency?: unknown;
  };
}

export class SocketIoLabReplayRecorderGatewayPort implements LabReplayGatewayPort {
  public constructor(
    private readonly gatewayEndpoint: string,
    private readonly acknowledgementTimeoutMilliseconds = 2_000,
  ) {
    if (!isGuestLoopbackHTTPEndpoint(gatewayEndpoint)) {
      throw new Error("Recorder Gateway endpoint must be a bare Guest-loopback HTTP URL");
    }
    if (
      !Number.isInteger(acknowledgementTimeoutMilliseconds) ||
      acknowledgementTimeoutMilliseconds < 100 ||
      acknowledgementTimeoutMilliseconds > 60_000
    ) {
      throw new Error("Recorder Gateway acknowledgement timeout must be between 100 and 60000 milliseconds");
    }
  }

  public async admitFrames(
    recorderGatewayRecorderCode: string,
    frames: LabReplayGatewayFrameAdmission[],
  ): Promise<
    | { state: "accepted"; ingressReceiptIds: string[] }
    | { state: "rejected" | "failed"; issue: LabRecorderRunnerIssue }
  > {
    const socket = io(this.gatewayEndpoint, {
      transports: ["websocket"],
      forceNew: true,
      reconnection: false,
      timeout: this.acknowledgementTimeoutMilliseconds,
    });
    try {
      await waitForSocketConnect(socket, this.acknowledgementTimeoutMilliseconds);
      const joined = await socket
        .timeout(this.acknowledgementTimeoutMilliseconds)
        .emitWithAck("join_vr", recorderGatewayRecorderCode) as GatewayAcknowledgement;
      if (
        joined.schemaVersion !== "v1" ||
        joined.state !== "accepted" ||
        !isIdentifier(joined.coldPathCaptureId)
      ) {
        return {
          state: "rejected",
          issue: acknowledgementIssue(
            "recorder-gateway-join-rejected",
            "Recorder Gateway rejected the replay recorder join",
            joined,
          ),
        };
      }
      const ingressReceiptIds: string[] = [];
      for (const admission of frames) {
        const acknowledgement = await socket
          .timeout(this.acknowledgementTimeoutMilliseconds)
          .emitWithAck("send_data_idempotent", {
            ...admission.identity,
            payload: encodeReplayFrame(recorderGatewayRecorderCode, admission.frame),
          }) as GatewayAcknowledgement;
        if (
          acknowledgement.schemaVersion !== "v1" ||
          acknowledgement.state !== "accepted" ||
          acknowledgement.receiptId !== admission.identity.receiptId
        ) {
          const issue = acknowledgementIssue(
            "recorder-gateway-replay-frame-rejected",
            "Recorder Gateway did not accept replay frame evidence",
            acknowledgement,
          );
          return {
            state: acknowledgement.state === "rejected" ? "rejected" : "failed",
            issue,
          };
        }
        ingressReceiptIds.push(acknowledgement.receiptId);
      }
      return { state: "accepted", ingressReceiptIds };
    } catch (error) {
      return {
        state: "failed",
        issue: {
          code: "recorder-gateway-replay-admission-outcome-unknown",
          message: `Runner could not determine replay frame admission outcome: ${errorMessage(error)}`,
          retryable: true,
          dependency: "recorder-gateway",
        },
      };
    } finally {
      socket.close();
    }
  }

  public async readLatestDelivery(
    ingressReceiptId: string,
  ): Promise<
    | {
      state: "available";
      deliveryReceiptId: string;
      attemptOutcome: "succeeded" | "failed" | "unavailable" | "unsupported" | "unknown";
      retryState: "not-scheduled" | "scheduled" | "exhausted";
    }
    | { state: "pending" }
    | { state: "failed"; issue: LabRecorderRunnerIssue }
  > {
    try {
      const response = await fetch(
        `${this.gatewayEndpoint}/v1/recorder-ingress/receipts/${encodeURIComponent(ingressReceiptId)}/delivery`,
        { headers: { accept: "application/json" } },
      );
      if (!response.ok) {
        return {
          state: "failed",
          issue: {
            code: "recorder-gateway-delivery-read-failed",
            message: `Recorder Gateway delivery read returned HTTP ${response.status}`,
            retryable: true,
            dependency: "recorder-gateway",
          },
        };
      }
      const decoded = await response.json() as unknown;
      if (!isRecord(decoded) || decoded.schemaVersion !== "v1" || typeof decoded.state !== "string") {
        return invalidDeliveryRead();
      }
      if (decoded.state === "empty") {
        return { state: "pending" };
      }
      if (decoded.state !== "available" || !isRecord(decoded.value)) {
        return {
          state: "failed",
          issue: responseIssue(
            "recorder-gateway-delivery-read-unavailable",
            "Recorder Gateway did not return available delivery evidence",
            decoded,
          ),
        };
      }
      const receipt = decoded.value;
      if (
        !isIdentifier(receipt.id) ||
        !isRecord(receipt.ingressReceiptReference) ||
        receipt.ingressReceiptReference.resourceType !== "ingress-receipt" ||
        receipt.ingressReceiptReference.resourceId !== ingressReceiptId ||
        !isRecord(receipt.outcome) ||
        !isDeliveryOutcome(receipt.outcome.state) ||
        !isRecord(receipt.retry) ||
        !isRetryState(receipt.retry.state)
      ) {
        return invalidDeliveryRead();
      }
      return {
        state: "available",
        deliveryReceiptId: receipt.id,
        attemptOutcome: receipt.outcome.state,
        retryState: receipt.retry.state,
      };
    } catch (error) {
      return {
        state: "failed",
        issue: {
          code: "recorder-gateway-delivery-read-outcome-unknown",
          message: `Runner could not determine Gateway delivery evidence: ${errorMessage(error)}`,
          retryable: true,
          dependency: "recorder-gateway",
        },
      };
    }
  }
}

function encodeReplayFrame(recorderCode: string, frame: LabReplayFrame): Buffer {
  const roomName = `Lab-${recorderCode}`;
  const payload = {
    vrcode: recorderCode,
    rooms: {
      [roomName]: {
        roomname: roomName,
        trks: frame.tracks.map((track) => replayTrackPayload(frame, track)),
      },
    },
  };
  return deflateSync(Buffer.from(JSON.stringify(payload), "utf8"));
}

function replayTrackPayload(frame: LabReplayFrame, track: LabReplayFrameTrack): object {
  const monitorType = VitalServerMonitorType[track.monitorType];
  if (monitorType === undefined) {
    throw new Error(`unsupported VitalServer monitor type ${track.monitorType}`);
  }
  const common = {
    id: track.outputTrackId,
    type: track.kind === 1 ? "wav" : "num",
    name: track.name,
    dname: track.deviceName,
    montype: monitorType,
    unit: track.unit,
    sourceTrack: `${track.deviceName}/${track.name}`,
    recs: [{
      dt: frame.outputTime,
      val: track.kind === 1 ? track.waveformValues : track.numericValue,
    }],
  };
  if (track.kind === 1) {
    return {
      ...common,
      srate: track.sampleRate,
      mindisp: track.minimumDisplay,
      maxdisp: track.maximumDisplay,
    };
  }
  return common;
}

// Published `.vital` TRACKINFO ids and realtime `send_data` wire names.
// Numeric enum reverse lookup is the conversion contract; unknown ids fail.
enum VitalServerMonitorType {
  ECG_WAV = 1, ECG_HR = 2, ECG_PVC = 3, IABP_WAV = 4, IABP_SBP = 5,
  IABP_DBP = 6, IABP_MBP = 7, PLETH_WAV = 8, PLETH_HR = 9, PLETH_SPO2 = 10,
  RESP_WAV = 11, RESP_RR = 12, CO2_WAV = 13, CO2_RR = 14, CO2_CONC = 15,
  NIBP_SBP = 16, NIBP_DBP = 17, NIBP_MBP = 18, BT = 19, CVP_WAV = 20,
  CVP_CVP = 21, EEG_BIS = 22, TV = 23, MV = 24, PIP = 25,
  AGENT1_NAME = 26, AGENT1_CONC = 27, AGENT2_NAME = 28, AGENT2_CONC = 29,
  DRUG1_NAME = 30, DRUG1_CE = 31, DRUG2_NAME = 32, DRUG2_CE = 33, CO = 34,
  EEG_SEF = 36, PEEP = 38, ECG_ST = 39, AGENT3_NAME = 40, AGENT3_CONC = 41,
  STO2_L = 42, STO2_R = 43, EEG_WAV = 44, FLUID_RATE = 45, FLUID_TOTAL = 46,
  SVV = 47, DRUG3_NAME = 49, DRUG3_CE = 50, FILT1_1 = 52, FILT1_2 = 53,
  FILT2_1 = 54, FILT2_2 = 55, FILT3_1 = 56, FILT3_2 = 57, FILT4_1 = 58,
  FILT4_2 = 59, FILT5_1 = 60, FILT5_2 = 61, FILT6_1 = 62, FILT6_2 = 63,
  FILT7_1 = 64, FILT7_2 = 65, FILT8_1 = 66, FILT8_2 = 67, PSI = 70,
  PVI = 71, SPHB = 72, ORI = 73, ASKNA = 75, PAP_SBP = 76, PAP_MBP = 77,
  PAP_DBP = 78, FEM_SBP = 79, FEM_MBP = 80, FEM_DBP = 81, EEG_SEFL = 82,
  EEG_SEFR = 83, EEG_SR = 84, TOF_RATIO = 85, TOF_CNT = 86, SKNA_WAV = 87,
  ICP = 88, CPP = 89, ICP_WAV = 90, PAP_WAV = 91, FEM_WAV = 92,
  ALARM_LEVEL = 93, EEGL_WAV = 95, EEGR_WAV = 96, ANII = 97, ANIM = 98,
  PTC_CNT = 99,
}

function waitForSocketConnect(socket: Socket, timeoutMilliseconds: number): Promise<void> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error("Socket.IO connect timed out"));
    }, timeoutMilliseconds);
    const onConnect = (): void => {
      cleanup();
      resolve();
    };
    const onError = (error: Error): void => {
      cleanup();
      reject(error);
    };
    const cleanup = (): void => {
      clearTimeout(timer);
      socket.off("connect", onConnect);
      socket.off("connect_error", onError);
    };
    socket.once("connect", onConnect);
    socket.once("connect_error", onError);
  });
}

function acknowledgementIssue(
  code: string,
  message: string,
  acknowledgement: GatewayAcknowledgement,
): LabRecorderRunnerIssue {
  return {
    code: typeof acknowledgement.issue?.code === "string" ? acknowledgement.issue.code : code,
    message: typeof acknowledgement.issue?.message === "string" ? acknowledgement.issue.message : message,
    retryable: typeof acknowledgement.issue?.retryable === "boolean" ? acknowledgement.issue.retryable : false,
    dependency: typeof acknowledgement.issue?.dependency === "string" ? acknowledgement.issue.dependency : "recorder-gateway",
  };
}

function responseIssue(code: string, message: string, value: Record<string, unknown>): LabRecorderRunnerIssue {
  const issue = isRecord(value.issue) ? value.issue : undefined;
  return {
    code: typeof issue?.code === "string" ? issue.code : code,
    message: typeof issue?.message === "string" ? issue.message : message,
    retryable: typeof issue?.retryable === "boolean" ? issue.retryable : true,
    dependency: typeof issue?.dependency === "string" ? issue.dependency : "recorder-gateway",
  };
}

function invalidDeliveryRead(): { state: "failed"; issue: LabRecorderRunnerIssue } {
  return {
    state: "failed",
    issue: {
      code: "recorder-gateway-delivery-receipt-invalid",
      message: "Recorder Gateway delivery response did not match its explicit receipt contract",
      retryable: true,
      dependency: "recorder-gateway",
    },
  };
}

function isDeliveryOutcome(value: unknown): value is "succeeded" | "failed" | "unavailable" | "unsupported" | "unknown" {
  return value === "succeeded" || value === "failed" || value === "unavailable" || value === "unsupported" || value === "unknown";
}

function isRetryState(value: unknown): value is "not-scheduled" | "scheduled" | "exhausted" {
  return value === "not-scheduled" || value === "scheduled" || value === "exhausted";
}

function isGuestLoopbackHTTPEndpoint(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "http:" &&
      (url.hostname === "127.0.0.1" || url.hostname === "[::1]" || url.hostname === "::1") &&
      url.username === "" &&
      url.password === "" &&
      url.pathname === "/" &&
      url.search === "" &&
      url.hash === "" &&
      url.port !== "";
  } catch {
    return false;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isIdentifier(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(value);
}

function errorMessage(value: unknown): string {
  return value instanceof Error ? value.message : "unknown error";
}
