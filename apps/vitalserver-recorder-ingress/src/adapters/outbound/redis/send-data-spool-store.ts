import type {
  SendDataSpoolStoreClaim,
  SendDataSpoolStorePort,
  SendDataSpoolStoreWriteResult,
} from "../../../application/ports/outbound/send-data-spool-store-port";
import type { SendDataReplayAttemptOptions, SendDataSpoolItem } from "../../../domain/send-data-spool-types";

"use strict";

const { beginSendDataReplayAttempt } = require("../../../domain/send-data-replay-policy");
const { sendDataFailureReasons } = require("../../../domain/send-data-ingress-contracts");
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
      return moveClaim(redis, claim, replayedKey, item);
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

module.exports = { createRedisSendDataSpoolStore };
