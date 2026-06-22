"use strict";

const assert = require("assert");
const test = require("node:test");
const { parseRespReply } = require("../../src/infrastructure/redis/client");

test("redis parser returns bulk string values for verification", () => {
  assert.deepStrictEqual(parseRespReply("+OK\r\n"), { complete: true, value: "OK" });
  assert.deepStrictEqual(parseRespReply("$12\r\n172.31.0.152\r\n"), {
    complete: true,
    value: "172.31.0.152",
  });
  assert.deepStrictEqual(parseRespReply("$-1\r\n"), { complete: true, value: null });
  assert.deepStrictEqual(parseRespReply("$12\r\n172.31"), { complete: false });
});
