import type { SendDataIngressPort } from "./ports/inbound/send-data-ingress-port";
import type { SendDataFailureSinkPort } from "./ports/outbound/send-data-failure-sink-port";
import type { SendDataRawArchivePort } from "./ports/outbound/send-data-raw-archive-port";
import type { SendDataSpoolAppendPort } from "./ports/outbound/send-data-spool-store-port";
import type {
  SendDataContext,
  SendDataPayloadSummary,
  SendDataRawArchiveConfig,
  SendDataSpoolConfig,
} from "../domain/send-data-spool-types";

"use strict";

const { evaluateSendDataBackpressure } = require("../domain/send-data-backpressure-policy");
const { sendDataFailureReasons } = require("../domain/send-data-ingress-contracts");
const { createSendDataSpoolItem } = require("../domain/send-data-spool-item");
const { recordSendDataFailure } = require("./send-data-failure-log");
const {
  recordSendDataSpoolAccepted,
  recordSendDataRawArchived,
  recordSendDataRawArchiveWriteFailed,
  recordSendDataSpoolRejected,
  recordSendDataSpoolSpooled,
  recordSendDataSpoolWriteFailed,
  sendDataSpoolState,
} = require("../observability/metrics");

type SendDataIngressServiceDependencies = {
  config: { spool: SendDataSpoolConfig; rawArchive?: SendDataRawArchiveConfig };
  failureSink?: SendDataFailureSinkPort;
  metrics: Record<string, unknown>;
  rawArchive?: SendDataRawArchivePort;
  spoolStore: SendDataSpoolAppendPort;
  now?: () => Date;
  idFactory?: () => string;
};

function createSendDataIngressService({
  config,
  failureSink,
  metrics,
  rawArchive,
  spoolStore,
  now,
  idFactory,
}: SendDataIngressServiceDependencies): SendDataIngressPort {
  return {
    async record(payload, context, payloadSummary) {
      if (!config.spool.enabled) {
        return {
          ok: true,
          outcome: "accepted",
          mode: config.spool.mode,
        };
      }

      const itemResult = createSendDataSpoolItem(payload, context, payloadSummary, { now, idFactory });
      const vrcode = itemResult.ok ? itemResult.item.vrcode : recorderCode(context, payloadSummary);
      if (!itemResult.ok) {
        recordSendDataSpoolRejected(metrics, vrcode, itemResult.reason, itemResult.message);
        recordSendDataFailure(failureSink, {
          kind: "send_data_invalid_payload",
          reason: itemResult.reason,
          message: itemResult.message,
          context,
          payloadSummary,
        });
        return {
          ok: false,
          outcome: "invalid_payload",
          reason: itemResult.reason,
          message: itemResult.message,
        };
      }

      if (config.rawArchive && config.rawArchive.enabled) {
        const archiveResult = await appendRawArchive(rawArchive, itemResult.item);
        if (!archiveResult.ok) {
          const reason = archiveResult.reason || sendDataFailureReasons.RAW_ARCHIVE_WRITE_FAILED;
          const message = archiveResult.message
            || (archiveResult.error && archiveResult.error.message)
            || "send_data raw archive write failed";
          recordSendDataRawArchiveWriteFailed(metrics, reason, message);
          recordSendDataFailure(failureSink, {
            kind: "send_data_raw_archive_write_failed",
            reason,
            message,
            item: itemResult.item,
          });
          return {
            ok: false,
            outcome: "raw_archive_write_failed",
            reason,
            message,
          };
        }
        recordSendDataRawArchived(metrics, itemResult.item, archiveResult);
      }

      const backpressure = evaluateSendDataBackpressure(
        config.spool,
        sendDataSpoolState(metrics),
        itemResult.item
      );
      if (backpressure.action === "reject") {
        recordSendDataSpoolRejected(metrics, itemResult.item.vrcode, backpressure.reason, backpressure.message);
        recordSendDataFailure(failureSink, {
          kind: "send_data_spool_rejected",
          reason: backpressure.reason,
          message: backpressure.message,
          item: itemResult.item,
        });
        return {
          ok: false,
          outcome: "rejected",
          reason: backpressure.reason,
          message: backpressure.message,
        };
      }

      recordSendDataSpoolAccepted(metrics, itemResult.item.vrcode, itemResult.item.payloadBytes);
      let appendResult;
      try {
        appendResult = await spoolStore.append(itemResult.item);
      } catch (error) {
        appendResult = { ok: false, error };
      }
      if (!appendResult.ok) {
        const message = appendResult.error && appendResult.error.message
          ? appendResult.error.message
          : "send_data spool write failed";
        if (appendResult.reason === sendDataFailureReasons.SPOOL_FULL) {
          recordSendDataSpoolRejected(
            metrics,
            itemResult.item.vrcode,
            sendDataFailureReasons.SPOOL_FULL,
            message
          );
          recordSendDataFailure(failureSink, {
            kind: "send_data_spool_rejected",
            reason: sendDataFailureReasons.SPOOL_FULL,
            message,
            item: itemResult.item,
          });
          return {
            ok: false,
            outcome: "rejected",
            reason: sendDataFailureReasons.SPOOL_FULL,
            message,
          };
        }
        recordSendDataSpoolWriteFailed(
          metrics,
          itemResult.item.vrcode,
          sendDataFailureReasons.SPOOL_WRITE_FAILED,
          message
        );
        recordSendDataFailure(failureSink, {
          kind: "send_data_spool_write_failed",
          reason: sendDataFailureReasons.SPOOL_WRITE_FAILED,
          message,
          item: itemResult.item,
        });
        return {
          ok: false,
          outcome: "spool_write_failed",
          reason: sendDataFailureReasons.SPOOL_WRITE_FAILED,
          message,
        };
      }

      recordSendDataSpoolSpooled(metrics, itemResult.item.vrcode, itemResult.item.payloadBytes, appendResult.depth);
      return {
        ok: true,
        outcome: "spooled",
        item: itemResult.item,
      };
    },
  };
}

async function appendRawArchive(rawArchive, item) {
  if (!rawArchive || typeof rawArchive.append !== "function") {
    return {
      ok: false,
      reason: sendDataFailureReasons.RAW_ARCHIVE_UNAVAILABLE,
      message: "send_data raw archive writer is not configured",
    };
  }
  try {
    return await rawArchive.append(item);
  } catch (error) {
    return { ok: false, reason: sendDataFailureReasons.RAW_ARCHIVE_WRITE_FAILED, error };
  }
}

function recorderCode(context: SendDataContext, payloadSummary: SendDataPayloadSummary) {
  if (payloadSummary && payloadSummary.vrcode) return String(payloadSummary.vrcode);
  if (context && context.joined_vrcode) return String(context.joined_vrcode);
  return "";
}

module.exports = { createSendDataIngressService };
