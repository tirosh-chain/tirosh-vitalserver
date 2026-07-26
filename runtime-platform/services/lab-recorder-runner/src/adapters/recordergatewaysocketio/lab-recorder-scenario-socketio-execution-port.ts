import { deflateSync } from "node:zlib";

import { io, type Socket } from "socket.io-client";

import type { LabRecorderScenarioExecutionHandle, LabRecorderScenarioExecutionPort } from "../../labrecorderrunnerapplication/lab-recorder-runner-ports.js";
import type { LabRecorderRunnerIssue, RecorderGatewayFinalizationReceiptReference, StartLabRecorderRunCommand } from "../../labrecorderrunnerdomain/lab-recorder-run-contracts.js";

interface RecorderGatewayJoinAcknowledgement {
  schemaVersion?: unknown;
  state?: unknown;
  coldPathCaptureId?: unknown;
}

interface RecorderGatewayPacketAcknowledgement {
  state?: unknown;
  issue?: { code?: unknown; message?: unknown; retryable?: unknown; dependency?: unknown };
}

// RecorderGatewaySocketIoLabRecorderScenarioExecutionPort owns only the
// socket, interval, packet emission, and exact Gateway finalization request.
// It has no persistence and cannot create a Lab or Archive state transition.
export class RecorderGatewaySocketIoLabRecorderScenarioExecutionPort implements LabRecorderScenarioExecutionPort {
  public constructor(private readonly gatewayEndpoint: string, private readonly acknowledgementTimeoutMilliseconds = 2_000) {
    if (!isGuestLoopbackHTTPEndpoint(gatewayEndpoint)) {
      throw new Error("Recorder Gateway endpoint must be a bare Guest-loopback HTTP URL");
    }
    if (!Number.isInteger(acknowledgementTimeoutMilliseconds) || acknowledgementTimeoutMilliseconds < 100 || acknowledgementTimeoutMilliseconds > 60_000) {
      throw new Error("Recorder Gateway acknowledgement timeout must be between 100 and 60000 milliseconds");
    }
  }

  public async startScenario(command: StartLabRecorderRunCommand): Promise<
    | { state: "started"; coldPathCaptureId: string; recorderGatewayRecorderId: string; handle: LabRecorderScenarioExecutionHandle }
    | { state: "rejected" | "failed"; issue: LabRecorderRunnerIssue }
  > {
    const socket = io(this.gatewayEndpoint, { transports: ["websocket"], forceNew: true, reconnection: false, timeout: this.acknowledgementTimeoutMilliseconds });
    try {
      await waitForSocketConnect(socket, this.acknowledgementTimeoutMilliseconds);
      const joined = await socket.timeout(this.acknowledgementTimeoutMilliseconds).emitWithAck("join_vr", command.recorderGatewayRecorderCode) as RecorderGatewayJoinAcknowledgement;
      if (joined.schemaVersion !== "v1" || joined.state !== "accepted" || !isIdentifier(joined.coldPathCaptureId)) {
        socket.close();
        return { state: "rejected", issue: acknowledgementIssue("recorder-gateway-join-rejected", "Recorder Gateway rejected the Lab recorder join", joined) };
      }
      const handle = new SocketIoLabRecorderScenarioExecutionHandle(socket, command, joined.coldPathCaptureId, this.gatewayEndpoint, this.acknowledgementTimeoutMilliseconds);
      const initial = await handle.emitOnePacket();
      if (initial !== undefined) {
        handle.close();
        return { state: initial.retryable === false ? "rejected" : "failed", issue: initial };
      }
      handle.startInterval();
      return { state: "started", coldPathCaptureId: joined.coldPathCaptureId, recorderGatewayRecorderId: `recorder-${command.recorderGatewayRecorderCode}`, handle };
    } catch (error) {
      socket.close();
      return { state: "failed", issue: { code: "recorder-gateway-connection-failed", message: `Lab recorder Runner could not establish the Recorder Gateway Socket.IO connection: ${errorMessage(error)}`, retryable: true, dependency: "recorder-gateway" } };
    }
  }
}

class SocketIoLabRecorderScenarioExecutionHandle implements LabRecorderScenarioExecutionHandle {
  private interval: NodeJS.Timeout | undefined;
  private emittedPacketCount = 0;
  private closed = false;
  private issue: LabRecorderRunnerIssue | undefined;
  private emission = Promise.resolve();

  public constructor(
    private readonly socket: Socket,
    private readonly command: StartLabRecorderRunCommand,
    private readonly coldPathCaptureId: string,
    private readonly gatewayEndpoint: string,
    private readonly acknowledgementTimeoutMilliseconds: number,
  ) {}

  public startInterval(): void {
    this.interval = setInterval(() => {
      this.emission = this.emission.then(async () => {
        if (this.closed || this.issue !== undefined) {
          return;
        }
        const emissionIssue = await this.emitOnePacket();
        if (emissionIssue !== undefined) {
          this.issue = emissionIssue;
          this.close();
        }
      });
    }, this.command.scenario.packetIntervalMilliseconds);
  }

  public async emitOnePacket(): Promise<LabRecorderRunnerIssue | undefined> {
    if (this.closed) {
      return { code: "lab-recorder-run-closed", message: "Lab recorder Runner cannot emit after its Socket.IO connection closed", retryable: true, dependency: "lab-recorder-runner" };
    }
    try {
      const acknowledgement = await this.socket.timeout(this.acknowledgementTimeoutMilliseconds).emitWithAck("send_data", buildCompressedLabFrame(this.command, this.emittedPacketCount)) as RecorderGatewayPacketAcknowledgement;
      if (acknowledgement.state !== "accepted") {
        return acknowledgementIssue("recorder-gateway-packet-rejected", "Recorder Gateway did not accept the Lab recorder packet", acknowledgement);
      }
      this.emittedPacketCount += 1;
      return undefined;
    } catch (error) {
      return { code: "recorder-gateway-packet-admission-failed", message: `Lab recorder Runner could not obtain a Recorder Gateway packet acknowledgement: ${errorMessage(error)}`, retryable: true, dependency: "recorder-gateway" };
    }
  }

  public readEmittedPacketCount(): number {
    return this.emittedPacketCount;
  }

  public async stopAndFinalize(requestId: string): Promise<{ state: "finalized"; finalizationReceipt: RecorderGatewayFinalizationReceiptReference } | { state: "rejected" | "failed"; issue: LabRecorderRunnerIssue }> {
    if (this.issue !== undefined) {
      return { state: "failed", issue: this.issue };
    }
    if (this.emittedPacketCount < this.command.scenario.minimumPacketCountBeforeStop) {
      return { state: "rejected", issue: { code: "lab-recorder-run-minimum-packet-count-not-reached", message: "Lab recorder run cannot finalize before its declared minimum accepted packet count", retryable: true, dependency: "lab-recorder-runner" } };
    }
    if (this.interval !== undefined) {
      clearInterval(this.interval);
      this.interval = undefined;
    }
    await this.emission;
    try {
      const expectedCaptureRevision = await this.readCurrentCaptureRevision();
      if (typeof expectedCaptureRevision !== "number") {
        return { state: "failed", issue: { code: "recorder-gateway-capture-read-failed", message: "Lab recorder Runner could not obtain the explicit current Gateway capture revision before finalization", retryable: true, dependency: "recorder-gateway" } };
      }
      const response = await fetch(`${this.gatewayEndpoint}/v1/recorder-cold-path/captures/${encodeURIComponent(this.coldPathCaptureId)}:finalize`, {
        method: "POST",
        headers: { "content-type": "application/json", accept: "application/json" },
        body: JSON.stringify({ schemaVersion: "v1", requestId, coldPathCaptureId: this.coldPathCaptureId, expectedCaptureRevision }),
      });
      const decoded = await response.json() as unknown;
      if (!response.ok) {
        return { state: response.status >= 500 ? "failed" : "rejected", issue: responseIssue("recorder-gateway-finalization-rejected", "Recorder Gateway did not finalize the Lab recorder cold-path capture", decoded, response.status >= 500) };
      }
      const receipt = this.finalizationReceipt(decoded);
      if (receipt === undefined) {
        return { state: "failed", issue: { code: "recorder-gateway-finalization-receipt-invalid", message: "Recorder Gateway finalization response lacks required receipt evidence", retryable: true, dependency: "recorder-gateway" } };
      }
      this.close();
      return { state: "finalized", finalizationReceipt: receipt };
    } catch (error) {
      return { state: "failed", issue: { code: "recorder-gateway-finalization-outcome-unknown", message: `Lab recorder Runner could not determine the Gateway finalization outcome: ${errorMessage(error)}`, retryable: true, dependency: "recorder-gateway" } };
    }
  }

  public close(): void {
    if (this.interval !== undefined) {
      clearInterval(this.interval);
      this.interval = undefined;
    }
    this.closed = true;
    this.socket.close();
  }

  private finalizationReceipt(value: unknown): RecorderGatewayFinalizationReceiptReference | undefined {
    if (!isRecord(value) || value.schemaVersion !== "v1" || !isIdentifier(value.id) || !isRecord(value.captureReference) || value.captureReference.resourceType !== "recorder-cold-path-capture" || value.captureReference.resourceId !== this.coldPathCaptureId || value.recorderId !== `recorder-${this.command.recorderGatewayRecorderCode}` || typeof value.finalizedAt !== "string" || value.finalizedAt === "") {
      return undefined;
    }
    return { kind: "recorder-gateway-cold-path-finalization-receipt", id: value.id, captureId: this.coldPathCaptureId, recorderId: value.recorderId, finalizedAt: value.finalizedAt };
  }

  private async readCurrentCaptureRevision(): Promise<number | undefined> {
    const response = await fetch(`${this.gatewayEndpoint}/v1/recorder-cold-path/captures/${encodeURIComponent(this.coldPathCaptureId)}`, { headers: { accept: "application/json" } });
    if (!response.ok) {
      return undefined;
    }
    const decoded = await response.json() as unknown;
    if (!isRecord(decoded) || decoded.schemaVersion !== "v1" || decoded.state !== "available" || !isRecord(decoded.value) || decoded.value.id !== this.coldPathCaptureId || decoded.value.recorderId !== `recorder-${this.command.recorderGatewayRecorderCode}` || decoded.value.state !== "capturing" || !Number.isInteger(decoded.value.resourceRevision) || (decoded.value.resourceRevision as number) < 1) {
      return undefined;
    }
    return decoded.value.resourceRevision as number;
  }
}

function buildCompressedLabFrame(command: StartLabRecorderRunCommand, packetIndex: number): Buffer {
  const timestamp = Date.now() / 1000;
  const waveformOffset = packetIndex % 4;
  const roomName = `Lab-${command.virtualRecorderId}`;
  const frame = {
    rooms: {
      [roomName]: {
        roomname: roomName,
        trks: [
          { name: "HR", dname: "VitalServer-Lab", montype: "ECG_HR", type: "num", unit: "/min", recs: [{ dt: timestamp, val: 75 }] },
          { name: "ECG", dname: "VitalServer-Lab", montype: "ECG_WAV", type: "wav", srate: 125, unit: "mV", mindisp: -2, maxdisp: 2, recs: [{ dt: timestamp, val: [0.05 + waveformOffset * 0.01, 0.8, 0.1, -0.2, 0.05] }] },
          { name: "SPO2", dname: "VitalServer-Lab", montype: "PLETH_SPO2", type: "num", unit: "%", recs: [{ dt: timestamp, val: 98 }] },
        ],
      },
    },
  };
  return deflateSync(Buffer.from(JSON.stringify(frame), "utf8"));
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

function acknowledgementIssue(code: string, message: string, acknowledgement: RecorderGatewayPacketAcknowledgement | RecorderGatewayJoinAcknowledgement): LabRecorderRunnerIssue {
  const issue = "issue" in acknowledgement ? acknowledgement.issue : undefined;
  return {
    code: typeof issue?.code === "string" ? issue.code : code,
    message: typeof issue?.message === "string" ? issue.message : message,
    retryable: typeof issue?.retryable === "boolean" ? issue.retryable : false,
    dependency: typeof issue?.dependency === "string" ? issue.dependency : "recorder-gateway",
  };
}

function responseIssue(code: string, message: string, value: unknown, retryable: boolean): LabRecorderRunnerIssue {
  if (isRecord(value) && isRecord(value.issue)) {
    return {
      code: typeof value.issue.code === "string" ? value.issue.code : code,
      message: typeof value.issue.message === "string" ? value.issue.message : message,
      retryable: typeof value.issue.retryable === "boolean" ? value.issue.retryable : retryable,
      dependency: typeof value.issue.dependency === "string" ? value.issue.dependency : "recorder-gateway",
    };
  }
  return { code, message, retryable, dependency: "recorder-gateway" };
}

function isGuestLoopbackHTTPEndpoint(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "http:" && (url.hostname === "127.0.0.1" || url.hostname === "[::1]" || url.hostname === "::1") && url.username === "" && url.password === "" && url.pathname === "/" && url.search === "" && url.hash === "" && url.port !== "";
  } catch {
    return false;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isIdentifier(value: unknown): value is string {
  return typeof value === "string" && /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/.test(value);
}

function errorMessage(value: unknown): string {
  return value instanceof Error ? value.message : "unknown error";
}
