"use strict";

const assert = require("assert");
const { EventEmitter } = require("events");
const test = require("node:test");
const {
  createRedisClient,
  isRedisQueueFullError,
  parseRespReply,
} = require("../../src/adapters/outbound/redis/client");

test("redis parser returns bulk string values for verification", () => {
  assert.deepStrictEqual(parseRespReply("+OK\r\n"), { complete: true, value: "OK" });
  assert.deepStrictEqual(parseRespReply("$12\r\n172.31.0.152\r\n"), {
    complete: true,
    value: "172.31.0.152",
  });
  assert.deepStrictEqual(parseRespReply("$-1\r\n"), { complete: true, value: null });
  assert.deepStrictEqual(parseRespReply("$12\r\n172.31"), { complete: false });
});

test("redis parser returns array values for range reads", () => {
  assert.deepStrictEqual(parseRespReply("*2\r\n$3\r\none\r\n$3\r\ntwo\r\n"), {
    complete: true,
    value: ["one", "two"],
  });
  assert.deepStrictEqual(parseRespReply("*2\r\n$3\r\none\r\n$3\r\n"), { complete: false });
});

test("redis client reuses one connection for queued commands", async () => {
  let replies = 0;
  const sockets: any[] = [];
  const redis = createRedisClient(redisConfig(6379), fakeRedisDependencies(() => {
    const socket = new FakeRedisSocket((chunk) => {
      const commands = chunk.toString("utf8").split("*").length - 1;
      for (let index = 0; index < commands; index += 1) {
        replies += 1;
        socket.emitData(`:${replies}\r\n`);
      }
    });
    sockets.push(socket);
    return socket;
  }));

  const results = await Promise.all([
    redisCommand(redis, ["RPUSH", "key", "a"]),
    redisCommand(redis, ["RPUSH", "key", "b"]),
    redisCommand(redis, ["LLEN", "key"]),
  ]);

  assert.deepStrictEqual(results, [1, 2, 3]);
  assert.strictEqual(sockets.length, 1);
});

test("redis client retries a command after a connection failure", async () => {
  const sockets: any[] = [];
  const redis = createRedisClient(redisConfig(6379, {
    retry: { maxAttempts: 2, baseDelayMs: 1, maxDelayMs: 1, jitterRatio: 0 },
  }), fakeRedisDependencies(() => {
    const socket = new FakeRedisSocket(() => {
      if (sockets.length === 1) {
        socket.destroy();
        return;
      }
      socket.emitData("+OK\r\n");
    });
    sockets.push(socket);
    return socket;
  }));

  const result = await redisCommand(redis, ["SET", "key", "value"]);

  assert.strictEqual(result, "OK");
  assert.strictEqual(sockets.length, 2);
});

test("redis client reports queue overflow explicitly", async () => {
  const redis = createRedisClient(redisConfig(6379, {
    timeoutMs: 10,
    maxQueueLength: 1,
    retry: { maxAttempts: 1, baseDelayMs: 1, maxDelayMs: 1, jitterRatio: 0 },
  }), fakeRedisDependencies(() => {
    return new FakeRedisSocket(() => {});
  }));
  const first = redisCommand(redis, ["PING"]);
  let overflowError;
  await assert.rejects(
    () => redisCommand(redis, ["PING"]),
    (error) => {
      overflowError = error;
      return /redis command queue full length=1/.test(error.message);
    }
  );
  assert.strictEqual(isRedisQueueFullError(overflowError), true);
  await assert.rejects(() => first, /redis command timeout/);
});

test("redis client does not retry explicit Redis error replies", async () => {
  const sockets: any[] = [];
  const redis = createRedisClient(redisConfig(6379), fakeRedisDependencies(() => {
    const socket = new FakeRedisSocket(() => {
      socket.emitData("-ERR unknown command\r\n");
    });
    sockets.push(socket);
    return socket;
  }));

  await assert.rejects(() => redisCommand(redis, ["BAD"]), /ERR unknown command/);
  assert.strictEqual(sockets.length, 1);
});

function redisCommand(redis, args) {
  return new Promise((resolve, reject) => {
    redis.command(args, (error, reply) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(reply);
    });
  });
}

function redisConfig(port, overrides = {}) {
  return {
    host: "127.0.0.1",
    port,
    timeoutMs: 100,
    maxQueueLength: 100,
    retry: { maxAttempts: 3, baseDelayMs: 1, maxDelayMs: 1, jitterRatio: 0 },
    ...overrides,
  };
}

function fakeRedisDependencies(createSocket) {
  return {
    createConnection() {
      const socket = createSocket();
      process.nextTick(() => socket.emit("connect"));
      return socket;
    },
  };
}

class FakeRedisSocket extends EventEmitter {
  constructor(onWrite) {
    super();
    this.onWrite = onWrite;
  }

  setNoDelay() {}

  setTimeout() {}

  write(chunk) {
    this.onWrite(chunk);
  }

  destroy() {
    process.nextTick(() => this.emit("close"));
  }

  emitData(data) {
    process.nextTick(() => this.emit("data", Buffer.from(data)));
  }
}
