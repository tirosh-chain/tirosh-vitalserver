"use strict";

const net = require("net");

function createRedisClient(config, dependencies: any = {}) {
  const createConnection = dependencies.createConnection || net.createConnection;
  const state = {
    socket: null,
    connected: false,
    connecting: false,
    buffer: "",
    active: null,
    queue: [],
  };
  const retry = config.retry || {};
  const maxQueueLength = positiveNumber(config.maxQueueLength, 50000);
  const maxAttempts = positiveNumber(retry.maxAttempts, 3);
  const baseDelayMs = positiveNumber(retry.baseDelayMs, 25);
  const maxDelayMs = positiveNumber(retry.maxDelayMs, 500);
  const jitterRatio = nonNegativeNumber(retry.jitterRatio, 0.2);

  return {
    command(args, callback) {
      if (state.queue.length >= maxQueueLength) {
        if (callback) callback(redisQueueFullError(state.queue.length));
        return;
      }
      state.queue.push({
        args,
        callback,
        attempts: 0,
        timer: null,
      });
      drainQueue();
    },
  };

  function drainQueue() {
    if (state.active || state.queue.length === 0) return;
    if (!state.connected) {
      connect();
      return;
    }
    sendNext();
  }

  function connect() {
    if (state.connected || state.connecting) return;
    state.connecting = true;
    state.buffer = "";
    const socket = createConnection({ host: config.host, port: config.port });
    state.socket = socket;
    socket.setNoDelay(true);
    socket.on("connect", () => {
      state.connected = true;
      state.connecting = false;
      drainQueue();
    });
    socket.on("data", onData);
    socket.on("error", onSocketFailure);
    socket.on("timeout", () => onSocketFailure(new Error("redis connection timeout")));
    socket.on("close", () => {
      state.connected = false;
      state.connecting = false;
      if (state.socket === socket) state.socket = null;
      if (state.active) {
        retryOrComplete(state.active, new Error("redis connection closed"));
      }
    });
    socket.setTimeout(config.timeoutMs);
  }

  function sendNext() {
    if (state.active || !state.connected || !state.socket) return;
    const command = state.queue.shift();
    if (!command) return;
    state.active = command;
    command.attempts += 1;
    command.timer = setTimeout(() => {
      retryOrComplete(command, new Error("redis command timeout"));
      closeSocket();
    }, config.timeoutMs);
    try {
      state.socket.write(encodeResp(command.args));
    } catch (error) {
      retryOrComplete(command, error);
      closeSocket();
    }
  }

  function onData(chunk) {
    if (!state.active) return;
    state.buffer += chunk.toString("utf8");
    const reply = parseRespReply(state.buffer);
    if (!reply.complete) return;
    const command = state.active;
    state.active = null;
    state.buffer = "";
    clearCommandTimer(command);
    if (reply.error) {
      if (command.callback) command.callback(reply.error);
      drainQueue();
      return;
    }
    if (command.callback) command.callback(null, reply.value);
    drainQueue();
  }

  function onSocketFailure(error) {
    if (state.active) {
      retryOrComplete(state.active, error);
    }
    closeSocket();
  }

  function retryOrComplete(command, error) {
    if (state.active === command) state.active = null;
    clearCommandTimer(command);
    if (command.attempts >= maxAttempts) {
      if (command.callback) command.callback(error);
      drainQueue();
      return;
    }
    const delayMs = retryDelayMs(command.attempts);
    setTimeout(() => {
      state.queue.unshift(command);
      drainQueue();
    }, delayMs);
  }

  function closeSocket() {
    state.connected = false;
    state.connecting = false;
    state.buffer = "";
    if (state.socket) {
      state.socket.destroy();
      state.socket = null;
    }
  }

  function clearCommandTimer(command) {
    if (!command.timer) return;
    clearTimeout(command.timer);
    command.timer = null;
  }

  function retryDelayMs(attempts) {
    const exponential = Math.min(maxDelayMs, baseDelayMs * Math.pow(2, Math.max(0, attempts - 1)));
    if (jitterRatio === 0) return exponential;
    const jitter = exponential * jitterRatio;
    return Math.max(0, Math.round(exponential - jitter + Math.random() * jitter * 2));
  }
}

function parseRespReply(data) {
  const parsed = parseRespValue(data, 0);
  if (!parsed.complete) return { complete: false };
  if (parsed.error) return { complete: true, error: parsed.error };
  return { complete: true, value: parsed.value };
}

function parseRespValue(data, offset) {
  if (!data || offset >= data.length) return { complete: false };
  const prefix = data[offset];
  if (prefix === "-") {
    const end = data.indexOf("\r\n", offset);
    if (end < 0) return { complete: false };
    return { complete: true, nextOffset: end + 2, error: new Error(data.slice(offset + 1, end)) };
  }
  if (prefix === "+" || prefix === ":") {
    const end = data.indexOf("\r\n", offset);
    if (end < 0) return { complete: false };
    const value = data.slice(offset + 1, end);
    return {
      complete: true,
      nextOffset: end + 2,
      value: prefix === ":" ? Number.parseInt(value, 10) : value,
    };
  }
  if (prefix === "$") {
    const end = data.indexOf("\r\n", offset);
    if (end < 0) return { complete: false };
    const byteLength = Number.parseInt(data.slice(offset + 1, end), 10);
    if (!Number.isFinite(byteLength)) {
      return { complete: true, error: new Error("invalid redis bulk string length") };
    }
    if (byteLength < 0) return { complete: true, nextOffset: end + 2, value: null };
    const valueStart = end + 2;
    const valueEnd = valueStart + byteLength;
    if (data.length < valueEnd + 2) return { complete: false };
    return { complete: true, nextOffset: valueEnd + 2, value: data.slice(valueStart, valueEnd) };
  }
  if (prefix === "*") {
    const end = data.indexOf("\r\n", offset);
    if (end < 0) return { complete: false };
    const length = Number.parseInt(data.slice(offset + 1, end), 10);
    if (!Number.isFinite(length)) {
      return { complete: true, error: new Error("invalid redis array length") };
    }
    if (length < 0) return { complete: true, nextOffset: end + 2, value: null };
    const values = [];
    let cursor = end + 2;
    for (let index = 0; index < length; index += 1) {
      const item = parseRespValue(data, cursor);
      if (!item.complete) return { complete: false };
      if (item.error) return item;
      values.push(item.value);
      cursor = item.nextOffset;
    }
    return { complete: true, nextOffset: cursor, value: values };
  }
  return { complete: true, error: new Error("unsupported redis reply") };
}

function encodeResp(args) {
  return `*${args.length}\r\n${args.map((arg) => {
    const value = Buffer.from(String(arg));
    return `$${value.length}\r\n${value.toString()}\r\n`;
  }).join("")}`;
}

function positiveNumber(value, fallback) {
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function nonNegativeNumber(value, fallback) {
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}

function redisQueueFullError(length) {
  const error: any = new Error(`redis command queue full length=${length}`);
  error.code = "REDIS_COMMAND_QUEUE_FULL";
  error.queueLength = length;
  return error;
}

function isRedisQueueFullError(error) {
  return Boolean(error && error.code === "REDIS_COMMAND_QUEUE_FULL");
}

module.exports = { createRedisClient, isRedisQueueFullError, parseRespReply };
