import type { AddressInfo } from "node:net";
import type { Server as HttpServer } from "node:http";

import type { Server as SocketIoServer } from "socket.io";

import { attachRecorderGatewaySocketIoIngress } from "./adapters/recordergatewayinbound/recorder-gateway-socketio-ingress-server.js";
import { createRecorderGatewayControlHTTPServer } from "./adapters/recordergatewayinbound/recorder-gateway-control-http-server.js";
import { GuestRuntimeObservationCatalogClient } from "./adapters/guestruntimeobservationcatalog/guest-runtime-observation-catalog-client.js";
import { GuestRuntimeArchiveSourceAdmissionClient } from "./adapters/guestruntimearchive/guest-runtime-archive-source-admission-client.js";
import { FileRecorderGatewayIngressDurableStateStore } from "./adapters/recordergatewayingressdurablestatefile/file-recorder-gateway-ingress-durable-state-store.js";
import { FileRecorderVitalUploadSpool } from "./adapters/recordervitaluploadspoolfile/file-recorder-vital-upload-spool.js";
import { SocketIoVitalServerPacketDeliveryPort } from "./adapters/vitalserverpacketdeliverysocketio/socketio-vital-server-packet-delivery-port.js";
import {
  CryptoRecorderGatewayIdentifierGenerator,
  RecorderGatewayIngressAndColdPathApplicationService,
  type RecorderGatewayDeliveryReplayRunResult,
  type RecorderGatewayIngressAndColdPathServiceConfiguration,
} from "./recordergatewayapplication/recorder-gateway-ingress-and-cold-path-application-service.js";
import { SystemRecorderGatewayClock } from "./recordergatewayapplication/recorder-gateway-ingress-and-cold-path-application-ports.js";
import {
  RecorderGatewayVitalUploadApplicationService,
  SystemRecorderVitalUploadClock,
  type RecorderVitalUploadRecoveryRunResult,
} from "./recordergatewayapplication/recorder-gateway-vital-upload-application-service.js";

export interface RecorderGatewayRuntimeConfiguration extends RecorderGatewayIngressAndColdPathServiceConfiguration {
  stateDirectory: string;
  vitalServerDeliveryURL: string;
  vitalServerDeliveryAcknowledgementTimeoutMs: number;
  replayIntervalMs: number;
  guestRuntimeObservationCatalogEndpoint: string;
  guestRuntimeObservationCatalogBearerToken: string;
  recorderVitalUploadMaximumBytes: number;
  recorderVitalUploadRecoveryIntervalMs: number;
  recorderVitalUploadRecoveryMaxItems: number;
  guestRuntimeArchiveSourceAdmissionEndpoint: string;
  guestRuntimeArchiveSourceAdmissionBearerToken: string;
  guestRuntimeArchiveSourceAdmissionRequestTimeoutMs: number;
}

export interface RecorderGatewayRuntime {
  ingressAndColdPathService: RecorderGatewayIngressAndColdPathApplicationService;
  vitalUploadService: RecorderGatewayVitalUploadApplicationService;
  recoverVitalUploads(): Promise<RecorderVitalUploadRecoveryRunResult>;
  start(host: string, port: number): Promise<AddressInfo>;
  close(): Promise<void>;
}

export async function createRecorderGatewayRuntime(configuration: RecorderGatewayRuntimeConfiguration): Promise<RecorderGatewayRuntime> {
  if (
    configuration.stateDirectory === ""
    || configuration.vitalServerDeliveryURL === ""
    || configuration.vitalServerDeliveryAcknowledgementTimeoutMs < 1
    || configuration.replayIntervalMs < 1
    || configuration.guestRuntimeObservationCatalogEndpoint === ""
    || configuration.guestRuntimeObservationCatalogBearerToken === ""
    || !Number.isSafeInteger(configuration.recorderVitalUploadMaximumBytes)
    || configuration.recorderVitalUploadMaximumBytes < 1
    || !Number.isSafeInteger(configuration.recorderVitalUploadRecoveryIntervalMs)
    || configuration.recorderVitalUploadRecoveryIntervalMs < 1
    || !Number.isSafeInteger(configuration.recorderVitalUploadRecoveryMaxItems)
    || configuration.recorderVitalUploadRecoveryMaxItems < 1
    || configuration.recorderVitalUploadRecoveryMaxItems > 1000
    || configuration.guestRuntimeArchiveSourceAdmissionEndpoint === ""
    || configuration.guestRuntimeArchiveSourceAdmissionBearerToken === ""
    || !Number.isSafeInteger(configuration.guestRuntimeArchiveSourceAdmissionRequestTimeoutMs)
    || configuration.guestRuntimeArchiveSourceAdmissionRequestTimeoutMs < 1
  ) {
    throw new Error("Recorder Gateway runtime configuration is incomplete");
  }
  const identifiers = new CryptoRecorderGatewayIdentifierGenerator();
  const ingressAndColdPathService = new RecorderGatewayIngressAndColdPathApplicationService(
    new FileRecorderGatewayIngressDurableStateStore(configuration.stateDirectory),
    new SocketIoVitalServerPacketDeliveryPort({
      vitalServerDeliveryURL: configuration.vitalServerDeliveryURL,
      acknowledgementTimeoutMs: configuration.vitalServerDeliveryAcknowledgementTimeoutMs,
      vitalServerProviderID: configuration.provider.id,
    }),
    new SystemRecorderGatewayClock(),
    identifiers,
    configuration,
  );
  await ingressAndColdPathService.initializeRecorderGatewayIngressDurableState();
  const observationPublisher = GuestRuntimeObservationCatalogClient.create(
    configuration.guestRuntimeObservationCatalogEndpoint,
    configuration.guestRuntimeObservationCatalogBearerToken,
  );
  const vitalUploadService = new RecorderGatewayVitalUploadApplicationService(
    new FileRecorderVitalUploadSpool({
      stateDirectory: configuration.stateDirectory,
      maximumUploadBytes: configuration.recorderVitalUploadMaximumBytes,
    }),
    GuestRuntimeArchiveSourceAdmissionClient.create({
      endpoint: configuration.guestRuntimeArchiveSourceAdmissionEndpoint,
      bearerToken: configuration.guestRuntimeArchiveSourceAdmissionBearerToken,
      requestTimeoutMs: configuration.guestRuntimeArchiveSourceAdmissionRequestTimeoutMs,
    }),
    new SystemRecorderVitalUploadClock(),
  );
  await vitalUploadService.initializeRecorderVitalUpload();
  const httpServer = createRecorderGatewayControlHTTPServer(
    ingressAndColdPathService,
    observationPublisher,
    vitalUploadService,
  );
  const socketServer = attachRecorderGatewaySocketIoIngress(httpServer, ingressAndColdPathService, identifiers);
  let replayTimer: NodeJS.Timeout | undefined;
  let replayRunInFlight: Promise<void> | undefined;
  let vitalUploadRecoveryTimer: NodeJS.Timeout | undefined;
  return {
    ingressAndColdPathService,
    vitalUploadService,
    recoverVitalUploads: async (): Promise<RecorderVitalUploadRecoveryRunResult> => (
      vitalUploadService.recoverRecorderVitalUploads(
        configuration.recorderVitalUploadRecoveryMaxItems,
      )
    ),
    start: async (host: string, port: number): Promise<AddressInfo> => {
      if (replayTimer !== undefined || vitalUploadRecoveryTimer !== undefined) {
        throw new Error("Recorder Gateway runtime is already listening");
      }
      reportVitalUploadRecovery(
        await vitalUploadService.recoverRecorderVitalUploads(
          configuration.recorderVitalUploadRecoveryMaxItems,
        ),
      );
      const address = await listenRecorderGatewayControlHTTPServer(httpServer, host, port);
      replayTimer = setInterval(() => {
        if (replayRunInFlight !== undefined) {
          return;
        }
        const run = runOneDueVitalServerDeliveryReplay(
          ingressAndColdPathService,
        );
        replayRunInFlight = run;
        void run.finally(() => {
          if (replayRunInFlight === run) {
            replayRunInFlight = undefined;
          }
        });
      }, configuration.replayIntervalMs);
      vitalUploadRecoveryTimer = setInterval(() => {
        void vitalUploadService.recoverRecorderVitalUploads(
          configuration.recorderVitalUploadRecoveryMaxItems,
        ).then(reportVitalUploadRecovery);
      }, configuration.recorderVitalUploadRecoveryIntervalMs);
      return address;
    },
    close: async (): Promise<void> => {
      if (replayTimer !== undefined) {
        clearInterval(replayTimer);
        replayTimer = undefined;
      }
      if (replayRunInFlight !== undefined) {
        await replayRunInFlight;
        replayRunInFlight = undefined;
      }
      if (vitalUploadRecoveryTimer !== undefined) {
        clearInterval(vitalUploadRecoveryTimer);
        vitalUploadRecoveryTimer = undefined;
      }
      await closeRecorderGatewaySocketIoIngressServer(socketServer);
      await closeRecorderGatewayControlHTTPServer(httpServer);
    },
  };
}

function reportVitalUploadRecovery(result: RecorderVitalUploadRecoveryRunResult): void {
  if (result.state === "completed") {
    return;
  }
  console.error(JSON.stringify({
    event: "recorder-gateway.vital-upload-recovery.incomplete",
    state: result.state,
    attempted: result.attempted,
    completed: result.completed,
    issue: result.issue,
  }));
}

async function runOneDueVitalServerDeliveryReplay(service: RecorderGatewayIngressAndColdPathApplicationService): Promise<void> {
  try {
    const result: RecorderGatewayDeliveryReplayRunResult = await service.replayOneDueVitalServerDelivery();
    if (result.state === "failed") {
      // This is operational evidence only. It contains a typed code and never
      // packet bytes, recorder code, endpoint, credential, or payload digest.
      console.error(JSON.stringify({ event: "recorder-gateway.delivery-replay.failed", issue: result.issue }));
    }
  } catch {
    console.error(JSON.stringify({
      event: "recorder-gateway.delivery-replay.failed",
      issue: {
        code: "gateway-delivery-replay-run-outcome-unknown",
        message: "Recorder Gateway delivery replay run did not return a typed outcome",
        retryable: true,
        dependency: "gateway-delivery-replay-worker",
      },
    }));
  }
}

function listenRecorderGatewayControlHTTPServer(server: HttpServer, host: string, port: number): Promise<AddressInfo> {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, host, () => {
      server.off("error", reject);
      const address = server.address();
      if (address === null || typeof address === "string") {
        reject(new Error("Recorder Gateway did not expose a TCP address"));
        return;
      }
      resolve(address);
    });
  });
}

function closeRecorderGatewaySocketIoIngressServer(server: SocketIoServer): Promise<void> {
  return new Promise((resolve) => {
    server.close(() => resolve());
  });
}

function closeRecorderGatewayControlHTTPServer(server: HttpServer): Promise<void> {
  if (!server.listening) {
    return Promise.resolve();
  }
  return new Promise((resolve, reject) => {
    server.close((error) => {
      if (error === undefined) {
        resolve();
        return;
      }
      reject(error);
    });
  });
}
