import { io } from "socket.io-client";

import type { VitalServerPacketDeliveryInput, VitalServerPacketDeliveryPort } from "../../recordergatewayapplication/recorder-gateway-ingress-and-cold-path-application-ports.js";
import type { VitalServerDeliveryAttemptOutcome } from "../../recordergatewaydomain/recorder-gateway-ingress-and-cold-path-contracts.js";

// SocketIoVitalServerPacketDeliveryConfiguration is an adapter-local transport
// configuration. The application selects the VitalServer provider identity;
// this adapter reports that exact identity in every failure evidence record.
export interface SocketIoVitalServerPacketDeliveryConfiguration {
  vitalServerDeliveryURL: string;
  acknowledgementTimeoutMs: number;
  vitalServerProviderID: string;
}

// SocketIoVitalServerPacketDeliveryPort speaks the VitalServer `send_data`
// acknowledgement protocol. It owns Socket.IO transport only; it does not
// decide whether the configured VitalServer is bundled or external.
export class SocketIoVitalServerPacketDeliveryPort implements VitalServerPacketDeliveryPort {
  public constructor(private readonly configuration: SocketIoVitalServerPacketDeliveryConfiguration) {
    if (configuration.vitalServerDeliveryURL === "" || configuration.acknowledgementTimeoutMs < 1 || configuration.vitalServerProviderID === "") {
      throw new Error("VitalServer Socket.IO delivery URL, acknowledgement timeout, and provider id are required");
    }
  }

  public async deliverRecorderPacketToVitalServer(input: VitalServerPacketDeliveryInput): Promise<VitalServerDeliveryAttemptOutcome> {
    return new Promise<VitalServerDeliveryAttemptOutcome>((resolve) => {
      const socket = io(this.configuration.vitalServerDeliveryURL, {
        transports: ["websocket", "polling"],
        forceNew: true,
        reconnection: false,
        timeout: this.configuration.acknowledgementTimeoutMs,
      });
      let settled = false;
      const complete = (outcome: VitalServerDeliveryAttemptOutcome): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timeout);
        socket.removeAllListeners();
        socket.close();
        resolve(outcome);
      };
      const timeout = setTimeout(() => {
        complete(this.vitalServerDeliveryFailure("vitalserver-delivery-acknowledgement-timeout", "configured VitalServer did not return an explicit packet-delivery acknowledgement", true, "unknown"));
      }, this.configuration.acknowledgementTimeoutMs);

      socket.on("connect", () => {
        try {
          const payload = input.payloadEncoding === "binary-string" ? Buffer.from(input.payload).toString("binary") : Buffer.from(input.payload);
          socket.emit("send_data", payload, (acknowledgement: unknown) => {
            complete(this.vitalServerDeliveryOutcomeFromAcknowledgement(acknowledgement));
          });
        } catch {
          complete(this.vitalServerDeliveryFailure("vitalserver-delivery-emit-failed", "Recorder Gateway could not emit the configured VitalServer packet-delivery event", true, "failed"));
        }
      });
      socket.on("connect_error", () => {
        complete(this.vitalServerDeliveryFailure("vitalserver-transport-unavailable", "Recorder Gateway could not connect to the configured VitalServer delivery endpoint", true, "unavailable"));
      });
      socket.on("error", () => {
        complete(this.vitalServerDeliveryFailure("vitalserver-socket-error", "configured VitalServer Socket.IO transport failed before packet-delivery acknowledgement", true, "unknown"));
      });
    });
  }

  private vitalServerDeliveryOutcomeFromAcknowledgement(value: unknown): VitalServerDeliveryAttemptOutcome {
    if (typeof value !== "object" || value === null) {
      return this.vitalServerDeliveryFailure("vitalserver-delivery-acknowledgement-invalid", "configured VitalServer returned an invalid packet-delivery acknowledgement", false, "failed");
    }
    const acknowledgement = value as { schemaVersion?: unknown; state?: unknown; issue?: unknown };
    if (acknowledgement.schemaVersion !== "v1" || typeof acknowledgement.state !== "string") {
      return this.vitalServerDeliveryFailure("vitalserver-delivery-acknowledgement-invalid", "configured VitalServer returned an invalid packet-delivery acknowledgement", false, "failed");
    }
    if (acknowledgement.state === "accepted") {
      return { state: "succeeded" };
    }
    if (acknowledgement.state === "unsupported") {
      return this.vitalServerDeliveryFailure("vitalserver-delivery-unsupported", "configured VitalServer explicitly does not support the packet-delivery contract", false, "unsupported");
    }
    return this.vitalServerDeliveryFailure("vitalserver-delivery-rejected", "configured VitalServer rejected the packet-delivery request", acknowledgement.state === "retryable-failure", "failed");
  }

  private vitalServerDeliveryFailure(code: string, message: string, retryable: boolean, state: VitalServerDeliveryAttemptOutcome["state"]): VitalServerDeliveryAttemptOutcome {
    return { state, issue: { code, message, retryable, dependency: this.configuration.vitalServerProviderID } };
  }
}
