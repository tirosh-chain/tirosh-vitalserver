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
const adminUserKey = "users:admin";

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
  if (key === adminUserKey && typeof value === "string") {
    try {
      value = JSON.stringify(withConfiguredAdminPassword(JSON.parse(value)));
    } catch (error) {
      // Keep the upstream value if it is not the expected JSON payload.
    }
  }

  return realRedisSet.call(this, key, value, ...rest);
};

function withConfiguredAdminPassword(user) {
  if (user && user.id === "admin") {
    user.password = adminPassword;
  }
  return user;
}

function syncConfiguredAdminPassword() {
  const client = redis.createClient(redisPort, redisHost);
  let completed = false;

  function close() {
    if (!completed) {
      completed = true;
      client.quit();
    }
  }

  client.on("ready", () => {
    client.get(adminUserKey, (getError, value) => {
      if (getError) {
        console.error("[tirosh] failed to read admin user:", getError.message);
        close();
        return;
      }

      let user;
      try {
        user = value ? JSON.parse(value) : null;
      } catch (error) {
        console.error("[tirosh] failed to parse admin user:", error.message);
        close();
        return;
      }

      if (!user || user.id !== "admin") {
        user = {
          id: "admin",
          password: adminPassword,
          name: "admin",
          email: "",
          admin_yn: "Y",
        };
      } else {
        user = withConfiguredAdminPassword(user);
      }

      client.sadd("users", "admin", () => {
        client.set(adminUserKey, JSON.stringify(user), (setError) => {
          if (setError) {
            console.error("[tirosh] failed to sync admin password:", setError.message);
          } else {
            console.log("[tirosh] admin password synced");
          }
          close();
        });
      });
    });
  });

  client.on("error", (error) => {
    console.error("[tirosh] admin password sync redis error:", error.message);
    close();
  });
}

setTimeout(syncConfiguredAdminPassword, 1000);

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
