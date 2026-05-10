"use strict";

const os = require("os");
const moduleLoader = require("module");
const redis = require("redis");

const realCpus = os.cpus.bind(os);
const minCpus = Number.parseInt(process.env.VITALSERVER_MIN_CPUS || "6", 10);
const adminPassword = process.env.VITALSERVER_ADMIN_PASSWORD || "admin";
const publicHost = process.env.VITALSERVER_PUBLIC_HOST || "localhost";
const publicPort = process.env.VITALSERVER_PUBLIC_PORT || "8080";

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

  if (request === "./include/db.js" && exported && exported.get_websocket_host) {
    exported.get_websocket_host = async function getPublicWebSocketHost() {
      return publicPort ? `${publicHost}:${publicPort}` : publicHost;
    };
  }

  return exported;
};
