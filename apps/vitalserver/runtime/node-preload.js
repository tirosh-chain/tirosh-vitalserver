"use strict";

const os = require("os");
const fs = require("fs");
const path = require("path");
const moduleLoader = require("module");
const redis = require("redis");
const { vitalFileWebPath } = require("./public-paths");
const { patchMyFilesScript } = require("./static-patches");

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

const realModuleLoad = moduleLoader._load;
const adminUserKey = "users:admin";
const redisRetryBaseMs = 500;
const redisRetryMaxMs = 5000;

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
  if (typeof next.retry_strategy !== "function") {
    next.retry_strategy = redisRetryStrategy;
  }

  return next;
}

function rewriteRedisCreateClientArgs(args) {
  const next = [...args];

  if (next.length === 0) {
    return [rewriteRedisOptions({ host: redisHost, port: redisPort })];
  }

  if (typeof next[0] === "object" && next[0] !== null) {
    next[0] = rewriteRedisOptions(next[0]);
    return next;
  }

  if (typeof next[0] === "number" && shouldRewriteRedisHost(next[1])) {
    next[0] = redisPort;
    next[1] = redisHost;
  }

  if (typeof next[0] === "number") {
    if (typeof next[2] === "object" && next[2] !== null) {
      next[2] = rewriteRedisOptions(next[2]);
    } else {
      next[2] = rewriteRedisOptions({});
    }
  }

  return next;
}

function redisRetryStrategy(options) {
  const delay = Math.min(
    redisRetryBaseMs + (options.attempt || 0) * redisRetryBaseMs,
    redisRetryMaxMs
  );

  if (options.error) {
    console.error(
      `[tirosh] redis reconnect scheduled code=${options.error.code || "unknown"} delay_ms=${delay}`
    );
  }

  return delay;
}

function attachRedisErrorHandler(client) {
  if (!client || client.__tiroshRedisErrorHandlerAttached) {
    return client;
  }

  client.on("error", (error) => {
    console.error("[tirosh] redis client error:", error.message);
  });
  client.on("reconnecting", (info) => {
    const delay = info && info.delay ? info.delay : "unknown";
    const attempt = info && info.attempt ? info.attempt : "unknown";
    console.error(`[tirosh] redis reconnecting attempt=${attempt} delay_ms=${delay}`);
  });

  Object.defineProperty(client, "__tiroshRedisErrorHandlerAttached", {
    value: true,
    enumerable: false,
  });

  return client;
}

function patchRedisSet(redisModule) {
  if (
    !redisModule ||
    !redisModule.RedisClient ||
    !redisModule.RedisClient.prototype ||
    redisModule.RedisClient.prototype.__tiroshRedisSetPatched
  ) {
    return;
  }

  const moduleRedisSet = redisModule.RedisClient.prototype.set;
  redisModule.RedisClient.prototype.set = function patchedRedisSet(key, value, ...rest) {
    if (key === adminUserKey && typeof value === "string") {
      try {
        value = JSON.stringify(withConfiguredAdminPassword(JSON.parse(value)));
      } catch (error) {
        // Keep the upstream value if it is not the expected JSON payload.
      }
    }

    return moduleRedisSet.call(this, key, value, ...rest);
  };
  Object.defineProperty(redisModule.RedisClient.prototype, "__tiroshRedisSetPatched", {
    value: true,
    enumerable: false,
  });
}

function patchRedisModule(redisModule) {
  if (!redisModule || !redisModule.createClient || redisModule.__tiroshRedisPatched) {
    return redisModule;
  }

  const realCreateClient = redisModule.createClient.bind(redisModule);
  redisModule.createClient = function patchedCreateClient(...args) {
    return attachRedisErrorHandler(realCreateClient(...rewriteRedisCreateClientArgs(args)));
  };
  patchRedisSet(redisModule);
  Object.defineProperty(redisModule, "__tiroshRedisPatched", {
    value: true,
    enumerable: false,
  });

  return redisModule;
}

patchRedisModule(redis);

function patchExpressModule(expressModule) {
  if (
    !expressModule ||
    !expressModule.response ||
    typeof expressModule.response.render !== "function" ||
    expressModule.response.__tiroshRenderPatched
  ) {
    return expressModule;
  }

  const realRender = expressModule.response.render;
  expressModule.response.render = function patchedRender(view, options, callback) {
    let nextOptions = options;
    if (view === "webview" && options && typeof options === "object") {
      const webPath = vitalFileWebPath(options.filename);
      if (webPath) {
        nextOptions = { ...options, path: webPath };
      }
    }

    return realRender.call(this, view, nextOptions, callback);
  };
  Object.defineProperty(expressModule.response, "__tiroshRenderPatched", {
    value: true,
    enumerable: false,
  });

  patchExpressStatic(expressModule);

  return expressModule;
}

function patchExpressStatic(expressModule) {
  if (
    !expressModule ||
    typeof expressModule.static !== "function" ||
    expressModule.__tiroshStaticPatched
  ) {
    return;
  }

  const realStatic = expressModule.static.bind(expressModule);
  expressModule.static = function patchedStatic(root, options) {
    const middleware = realStatic(root, options);
    if (typeof root !== "string" || path.basename(root) !== "static") {
      return middleware;
    }

    const myFilesScriptPath = path.join(root, "js", "my-files.js");
    return function patchedStaticMiddleware(request, response, next) {
      const requestPath = ((request && (request.path || request.url)) || "").split("?")[0];
      if (requestPath !== "/js/my-files.js" && requestPath !== "js/my-files.js") {
        return middleware(request, response, next);
      }

      fs.readFile(myFilesScriptPath, "utf8", (error, source) => {
        if (error) {
          next(error);
          return;
        }

        const patched = patchMyFilesScript(source);
        if (!patched.applied) {
          response
            .status(500)
            .type("text/plain")
            .send(`[tirosh] failed to patch my-files.js: ${patched.reason}`);
          return;
        }

        response.type("application/javascript").send(patched.source);
      });
    };
  };

  Object.defineProperty(expressModule, "__tiroshStaticPatched", {
    value: true,
    enumerable: false,
  });
}

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

  if (request === "express") {
    return patchExpressModule(exported);
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
