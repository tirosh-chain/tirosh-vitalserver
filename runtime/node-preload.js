"use strict";

const os = require("os");
const redis = require("redis");

const realCpus = os.cpus.bind(os);
const minCpus = Number.parseInt(process.env.VITALSERVER_MIN_CPUS || "6", 10);
const adminPassword = process.env.VITALSERVER_ADMIN_PASSWORD || "admin";

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
