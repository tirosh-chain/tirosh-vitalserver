import WebSocket from "ws";

// A deliberately small compatibility fixture for the Socket.IO v2 wire
// contract: Engine.IO v3 over WebSocket and Socket.IO protocol v4. Keeping the
// test client here avoids carrying an obsolete Socket.IO v2 client runtime (and
// its known vulnerable transitive dependency) in this repository.
export class SocketIoV2WireClient {
  private readonly acknowledgements = new Map<number, PendingAcknowledgement>();
  private readonly connected: Promise<void>;
  private resolveConnected: (() => void) | undefined;
  private rejectConnected: ((error: Error) => void) | undefined;
  private nextAcknowledgementID = 0;
  private closed = false;

  private constructor(private readonly socket: WebSocket) {
    this.connected = new Promise<void>((resolve, reject) => {
      this.resolveConnected = resolve;
      this.rejectConnected = reject;
    });
    socket.on("message", (data, isBinary) => {
      this.handleMessage(data, isBinary);
    });
    socket.on("error", (error) => {
      this.rejectConnection(error);
    });
    socket.on("close", (code, reason) => {
      this.closed = true;
      const detail = `Socket.IO v2 wire connection closed (${code} ${reason.toString("utf8")})`;
      this.rejectConnection(new Error(detail));
      this.rejectPending(new Error(`${detail} before acknowledgement`));
    });
  }

  public static async connect(url: string): Promise<SocketIoV2WireClient> {
    const target = `${url.replace(/^http/, "ws")}/socket.io/?EIO=3&transport=websocket`;
    const socket = new WebSocket(target);
    const client = new SocketIoV2WireClient(socket);
    await client.connected;
    return client;
  }

  public acknowledgeRecorderIngress(event: string, ...arguments_: unknown[]): Promise<unknown> {
    const acknowledgementID = this.nextAcknowledgementID;
    this.nextAcknowledgementID += 1;
    this.sendText(`42${acknowledgementID}${JSON.stringify([event, ...arguments_])}`);
    return this.waitForAcknowledgement(acknowledgementID, event);
  }

  public acknowledgeBinary(event: string, payload: Uint8Array): Promise<unknown> {
    const acknowledgementID = this.nextAcknowledgementID;
    this.nextAcknowledgementID += 1;
    const placeholder = { _placeholder: true, num: 0 };
    this.sendText(`451-${acknowledgementID}${JSON.stringify([event, placeholder])}`);
    this.socket.send(Buffer.concat([Buffer.from([4]), Buffer.from(payload)]));
    return this.waitForAcknowledgement(acknowledgementID, event);
  }

  public async close(): Promise<void> {
    if (this.closed || this.socket.readyState === WebSocket.CLOSED) {
      return;
    }
    await new Promise<void>((resolve) => {
      this.socket.once("close", () => resolve());
      this.socket.close();
    });
  }

  private handleMessage(data: WebSocket.RawData, isBinary: boolean): void {
    if (isBinary) {
      this.rejectConnection(new Error("Socket.IO v2 fixture received an unsupported binary server frame"));
      return;
    }
    const packet = Buffer.isBuffer(data) ? data.toString("utf8") : String(data);
    if (packet.startsWith("0")) {
      // Engine.IO v3 compatibility mode performs the Socket.IO namespace
      // connection server-side; the following Engine.IO message is `40`.
      // Sending another `40` would be an invalid second namespace connect.
      return;
    }
    if (packet.startsWith("2")) {
      // Engine.IO v3 heartbeat; preserve the optional ping payload.
      this.sendText(`3${packet.slice(1)}`);
      return;
    }
    if (packet === "40" || packet.startsWith("40{")) {
      this.resolveConnected?.();
      this.resolveConnected = undefined;
      this.rejectConnected = undefined;
      return;
    }
    if (packet.startsWith("43")) {
      this.receiveAcknowledgement(packet.slice(2));
      return;
    }
    if (packet.startsWith("44")) {
      this.rejectConnection(new Error(`Socket.IO v2 fixture received server error packet ${packet.slice(2)}`));
    }
  }

  private receiveAcknowledgement(encoded: string): void {
    const match = /^(\d+)(\[.*\])$/.exec(encoded);
    if (match === null) {
      this.rejectConnection(new Error("Socket.IO v2 fixture received a malformed acknowledgement"));
      return;
    }
    const acknowledgementID = Number.parseInt(match[1] ?? "", 10);
    const pending = this.acknowledgements.get(acknowledgementID);
    if (pending === undefined) {
      this.rejectConnection(new Error("Socket.IO v2 fixture received an acknowledgement with no pending event"));
      return;
    }
    let values: unknown;
    try {
      values = JSON.parse(match[2] ?? "");
    } catch {
      pending.reject(new Error("Socket.IO v2 fixture received acknowledgement JSON that could not be decoded"));
      this.acknowledgements.delete(acknowledgementID);
      return;
    }
    if (!Array.isArray(values) || values.length !== 1) {
      pending.reject(new Error("Socket.IO v2 fixture acknowledgement must contain one response value"));
      this.acknowledgements.delete(acknowledgementID);
      return;
    }
    clearTimeout(pending.timeout);
    this.acknowledgements.delete(acknowledgementID);
    pending.resolve(values[0]);
  }

  private waitForAcknowledgement(acknowledgementID: number, event: string): Promise<unknown> {
    return new Promise<unknown>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.acknowledgements.delete(acknowledgementID);
        reject(new Error(`Socket.IO v2 acknowledgement timed out for ${event}`));
      }, 2000);
      this.acknowledgements.set(acknowledgementID, { resolve, reject, timeout });
    });
  }

  private sendText(packet: string): void {
    if (this.closed || this.socket.readyState !== WebSocket.OPEN) {
      throw new Error("Socket.IO v2 fixture attempted to write on a closed connection");
    }
    this.socket.send(packet);
  }

  private rejectConnection(error: Error): void {
    if (this.rejectConnected !== undefined) {
      this.rejectConnected(error);
      this.resolveConnected = undefined;
      this.rejectConnected = undefined;
    }
  }

  private rejectPending(error: Error): void {
    for (const pending of this.acknowledgements.values()) {
      clearTimeout(pending.timeout);
      pending.reject(error);
    }
    this.acknowledgements.clear();
  }
}

interface PendingAcknowledgement {
  resolve(value: unknown): void;
  reject(error: Error): void;
  timeout: NodeJS.Timeout;
}
