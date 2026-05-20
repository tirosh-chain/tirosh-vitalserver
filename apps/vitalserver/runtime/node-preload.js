"use strict";

const os = require("os");
const moduleLoader = require("module");
const redis = require("redis");

const realCpus = os.cpus.bind(os);
const minCpus = Number.parseInt(process.env.VITALSERVER_MIN_CPUS || "8", 10);
const adminPassword = process.env.VITALSERVER_ADMIN_PASSWORD || "admin";
const publicHost = process.env.VITALSERVER_PUBLIC_HOST || "";
const publicPort = process.env.VITALSERVER_PUBLIC_PORT || "";
const redisHost = process.env.VITALSERVER_REDIS_HOST || "0.0.0.0";
const redisPort = Number.parseInt(process.env.VITALSERVER_REDIS_PORT || "6379", 10);

os.cpus = function patchedCpus() {
  const cpus = realCpus();
  if (!Number.isFinite(minCpus) || cpus.length >= minCpus) {
    return cpus;
  }

  const template = cpus[0] || {
    model: "virtual",
    speed: 0,
    times: { user: 0, nice: 0, sys: 0, idle: 0, irq: 0 },
  };

  return Array.from({ length: minCpus }, () => template);
};

const realRedisSet = redis.RedisClient.prototype.set;
const realModuleLoad = moduleLoader._load;

function shouldRewriteRedisHost(host) {
  return !host || host === "0.0.0.0" || host === "127.0.0.1" || host === "localhost";
}

function rewriteRedisOptions(options) {
  if (!options || typeof options !== "object" || Array.isArray(options)) {
    return options;
  }

  const next = { ...options };
  if (shouldRewriteRedisHost(next.host)) {
    next.host = redisHost;
  }
  if (!next.port || Number.parseInt(next.port, 10) === 6379) {
    next.port = redisPort;
  }

  return next;
}

function rewriteRedisCreateClientArgs(args) {
  const next = [...args];

  if (next.length === 0) {
    return [{ host: redisHost, port: redisPort }];
  }

  if (typeof next[0] === "object" && next[0] !== null) {
    next[0] = rewriteRedisOptions(next[0]);
    return next;
  }

  if (typeof next[0] === "number" && shouldRewriteRedisHost(next[1])) {
    next[0] = redisPort;
    next[1] = redisHost;
  }

  return next;
}

function patchRedisModule(redisModule) {
  if (!redisModule || !redisModule.createClient || redisModule.__tiroshRedisPatched) {
    return redisModule;
  }

  const realCreateClient = redisModule.createClient.bind(redisModule);
  redisModule.createClient = function patchedCreateClient(...args) {
    return realCreateClient(...rewriteRedisCreateClientArgs(args));
  };
  Object.defineProperty(redisModule, "__tiroshRedisPatched", {
    value: true,
    enumerable: false,
  });

  return redisModule;
}

patchRedisModule(redis);

redis.RedisClient.prototype.set = function patchedRedisSet(key, value, ...rest) {
  if (key === "users:admin" && typeof value === "string") {
    try {
      const user = JSON.parse(value);
      if (user && user.id === "admin") {
        user.password = adminPassword;
        value = JSON.stringify(user);
      }
    } catch (error) {
      // Keep the upstream value if it is not the expected JSON payload.
    }
  }

  return realRedisSet.call(this, key, value, ...rest);
};

moduleLoader._load = function patchedModuleLoad(request, parent, isMain) {
  const exported = realModuleLoad.call(this, request, parent, isMain);

  if (request === "redis") {
    return patchRedisModule(exported);
  }

  if (request === "./include/db.js" && exported && exported.get_websocket_host) {
    exported.get_websocket_host = async function getPublicWebSocketHost() {
      if (!publicHost) {
        return "/";
      }

      return publicPort ? `${publicHost}:${publicPort}` : publicHost;
    };
  }

  return exported;
};
