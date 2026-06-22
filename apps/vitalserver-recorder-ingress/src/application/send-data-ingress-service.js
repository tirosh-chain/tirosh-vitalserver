"use strict";

const { evaluateSendDataBackpressure } = require("../domain/send-data-backpressure-policy");
const { sendDataFailureReasons } = require("../domain/send-data-ingress-contracts");
const { createSendDataSpoolItem } = require("../domain/send-data-spool-item");
const {
  recordSendDataSpoolAccepted,
  recordSendDataSpoolRejected,
  recordSendDataSpoolSpooled,
  recordSendDataSpoolWriteFailed,
  sendDataSpoolState,
} = require("../observability/metrics");

function createSendDataIngressService({ config, metrics, spoolStore, now, idFactory }) {
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
        return {
          ok: false,
          outcome: "invalid_payload",
          reason: itemResult.reason,
          message: itemResult.message,
        };
      }

      const backpressure = evaluateSendDataBackpressure(
        config.spool,
        sendDataSpoolState(metrics),
        itemResult.item
      );
      if (backpressure.action === "reject") {
        recordSendDataSpoolRejected(metrics, itemResult.item.vrcode, backpressure.reason, backpressure.message);
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
        recordSendDataSpoolWriteFailed(
          metrics,
          itemResult.item.vrcode,
          sendDataFailureReasons.SPOOL_WRITE_FAILED,
          message
        );
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

function recorderCode(context, payloadSummary) {
  if (payloadSummary && payloadSummary.vrcode) return String(payloadSummary.vrcode);
  if (context && context.joined_vrcode) return String(context.joined_vrcode);
  return "";
}

module.exports = { createSendDataIngressService };
