"use strict";

const assert = require("assert");
const test = require("node:test");
const { createClientIpSelector } = require("../../src/infrastructure/http/client-ip");

test("client ip selector trusts forwarded headers only when enabled", () => {
  const req = {
    headers: { "x-forwarded-for": "172.31.0.152, 10.0.0.1" },
    socket: { remoteAddress: "::ffff:192.168.97.1" },
  };

  assert.deepStrictEqual(createClientIpSelector({ trustProxy: true }).select(req), {
    selected_ip: "172.31.0.152",
    selected_source: "x-forwarded-for",
    remote_address: "192.168.97.1",
    trust_proxy: true,
  });

  assert.deepStrictEqual(createClientIpSelector({ trustProxy: false }).select(req), {
    selected_ip: "192.168.97.1",
    selected_source: "remote-address",
    remote_address: "192.168.97.1",
    trust_proxy: false,
  });
});
