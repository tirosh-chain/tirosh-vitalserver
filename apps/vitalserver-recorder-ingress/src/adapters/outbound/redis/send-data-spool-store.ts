import type {
  SendDataSpoolStoreClaim,
  SendDataSpoolStorePort,
  SendDataSpoolStoreWriteResult,
} from "../../../application/ports/outbound/send-data-spool-store-port";
import type { SendDataReplayAttemptOptions, SendDataSpoolItem } from "../../../domain/send-data-spool-types";

"use strict";

const { beginSendDataReplayAttempt } = require("../../../domain/send-data-replay-policy");
const { sendDataFailureReasons } = require("../../../domain/send-data-ingress-contracts");
const { decideSendDataRealtimeRetention } = require("../../../domain/send-data-realtime-retention-policy");
const { isRedisQueueFullError } = require("./client");

type RedisCommandResult =
  | {
      ok: true;
      reply: unknown;
    }
  | {
      ok: false;
      error: Error;
    };

function createRedisSendDataSpoolStore(config, redis): SendDataSpoolStorePort {
  const inFlightKey = config.inFlightListKey || `${config.listKey}:in_flight`;
  const replayedKey = config.replayedListKey || `${config.listKey}:replayed`;
  const deadLetterKey = config.deadLetterListKey || `${config.listKey}:dead_letter`;
  const maxReplayedItems = Number.isFinite(config.maxReplayedItems) ? Number(config.maxReplayedItems) : null;

  return {
    append(item) {
      return new Promise((resolve) => {
        redis.command(["RPUSH", config.listKey, JSON.stringify(item)], (error, reply) => {
          if (error) {
            if (isRedisQueueFullError(error)) {
              resolve({ ok: false, reason: sendDataFailureReasons.SPOOL_FULL, error });
              return;
            }
            resolve({ ok: false, error });
            return;
          }
          resolve({ ok: true, depth: Number.isFinite(reply) ? reply : null });
        });
      });
    },
    async trimPending(maxItems) {
      if (!Number.isFinite(maxItems) || maxItems < 0) {
        return { ok: true, skippedRealtimeItems: 0, skippedRealtimeBytes: 0, preservedRealtimeItems: 0, depth: null };
      }
      const lengthResult = await redisCommand(redis, ["LLEN", config.listKey]);
      if (!lengthResult.ok) return lengthResult;
      const length = Number(lengthResult.reply);
      if (!Number.isFinite(length) || length <= maxItems) {
        return {
          ok: true,
          skippedRealtimeItems: 0,
          skippedRealtimeBytes: 0,
          preservedRealtimeItems: 0,
          depth: Number.isFinite(length) ? length : null,
        };
      }

      const candidateSkippedItems = Math.max(0, length - maxItems);
      const skippedRawResult = await redisCommand(redis, ["LRANGE", config.listKey, "0", String(candidateSkippedItems - 1)]);
      if (!skippedRawResult.ok) return skippedRawResult;
      const keptRawResult = maxItems === 0
        ? { ok: true, reply: [] }
        : await redisCommand(redis, ["LRANGE", config.listKey, String(-maxItems), "-1"]);
      if (!keptRawResult.ok) return keptRawResult;

      const skippedRecords = parseSpoolRawItems(skippedRawResult.reply);
      const keptRecords = parseSpoolRawItems(keptRawResult.reply);
      const retention = decideSendDataRealtimeRetention({
        skippedCandidates: skippedRecords,
        keptCandidates: keptRecords,
      });
      const trimStart = maxItems === 0 ? "1" : String(-maxItems);
      const trimEnd = maxItems === 0 ? "0" : "-1";
      const trimResult = await redisCommand(redis, ["LTRIM", config.listKey, trimStart, trimEnd]);
      if (!trimResult.ok) return trimResult;
      const preservedRawItems = skippedRecords
        .filter((record) => retention.preservedIndexes.includes(record.index))
        .map((record) => record.raw);
      if (preservedRawItems.length > 0) {
        const pushResult = await redisCommand(redis, ["RPUSH", config.listKey, ...preservedRawItems]);
        if (!pushResult.ok) return pushResult;
      }

      return {
        ok: true,
        skippedRealtimeItems: retention.skippedRealtimeItems,
        skippedRealtimeBytes: retention.skippedRealtimeBytes,
        skippedRealtimeByRecorder: retention.skippedRealtimeByRecorder,
        preservedRealtimeItems: retention.preservedRealtimeItems,
        depth: maxItems + retention.preservedRealtimeItems,
      };
    },
    async claim(options: SendDataReplayAttemptOptions = {}) {
      const rawResult = await redisCommand(redis, ["RPOPLPUSH", config.listKey, inFlightKey]);
      if (!rawResult.ok) return rawResult;
      if (rawResult.reply === null) return { ok: true, item: null, claim: null };

      const raw = String(rawResult.reply);
      let parsed;
      try {
        parsed = JSON.parse(raw);
      } catch (error) {
        return {
          ok: false,
          reason: sendDataFailureReasons.INVALID_PAYLOAD,
          message: error.message,
          raw,
          claim: { inFlightKey, raw },
        };
      }

      const attempt = beginSendDataReplayAttempt(parsed, options);
      if (!attempt.ok) {
        return {
          ...attempt,
          raw,
          claim: { inFlightKey, raw },
        };
      }

      const inFlightRaw = JSON.stringify(attempt.item);
      const removeResult = await redisCommand(redis, ["LREM", inFlightKey, "1", raw]);
      if (!removeResult.ok) return removeResult;
      const pushResult = await redisCommand(redis, ["RPUSH", inFlightKey, inFlightRaw]);
      if (!pushResult.ok) return pushResult;

      return {
        ok: true,
        item: attempt.item,
        claim: { inFlightKey, raw: inFlightRaw },
      };
    },
    async requeue(item, claim) {
      return moveClaim(redis, claim, config.listKey, item);
    },
    async markReplayed(item, claim) {
      const result = await moveClaim(redis, claim, replayedKey, item);
      if (!result.ok) return result;
      if (maxReplayedItems !== null && maxReplayedItems >= 0) {
        const trimStart = maxReplayedItems === 0 ? "1" : String(-maxReplayedItems);
        const trimEnd = maxReplayedItems === 0 ? "0" : "-1";
        const trimResult = await redisCommand(redis, ["LTRIM", replayedKey, trimStart, trimEnd]);
        if (!trimResult.ok) return trimResult;
      }
      return result;
    },
    async deadLetter(item, claim) {
      return moveClaim(redis, claim, deadLetterKey, item);
    },
  };
}

async function moveClaim(
  redis,
  claim: SendDataSpoolStoreClaim | null | undefined,
  targetKey: string,
  item: SendDataSpoolItem
): Promise<SendDataSpoolStoreWriteResult> {
  if (claim && claim.raw) {
    const removeResult = await redisCommand(redis, ["LREM", claim.inFlightKey, "1", claim.raw]);
    if (!removeResult.ok) return removeResult;
  }
  const pushResult = await redisCommand(redis, ["RPUSH", targetKey, JSON.stringify(item)]);
  if (!pushResult.ok) return pushResult;
  return {
    ok: true,
    depth: typeof pushResult.reply === "number" && Number.isFinite(pushResult.reply)
      ? pushResult.reply
      : null,
  };
}

function redisCommand(redis, args): Promise<RedisCommandResult> {
  return new Promise((resolve) => {
    redis.command(args, (error, reply) => {
      if (error) {
        resolve({ ok: false, error });
        return;
      }
      resolve({ ok: true, reply });
    });
  });
}

function parseSpoolRawItems(rawItems) {
  const records = [];
  const items = Array.isArray(rawItems) ? rawItems : [];
  items.forEach((raw, index) => {
    try {
      const item = JSON.parse(String(raw));
      records.push({
        index,
        raw: String(raw),
        vrcode: typeof item.vrcode === "string" && item.vrcode ? item.vrcode : null,
        payloadBytes: Number.isFinite(item && item.payloadBytes) ? Number(item.payloadBytes) : 0,
      });
    } catch (_error) {
      records.push({ index, raw: String(raw), vrcode: null, payloadBytes: 0 });
    }
  });
  return records;
}

module.exports = { createRedisSendDataSpoolStore };
