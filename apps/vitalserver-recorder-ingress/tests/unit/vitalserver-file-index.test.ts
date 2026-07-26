"use strict";

const assert = require("assert");
const test = require("node:test");
const zlib = require("zlib");
const {
  createVitalServerFileIndex,
} = require("../../src/adapters/outbound/http/vitalserver-file-index");

test("VitalServer file index adapter returns explicit matching evidence", async () => {
  const requests = [];
  const adapter = createVitalServerFileIndex(
    {
      baseUrl: "http://app",
      adminPassword: "secret",
      timeoutMs: 1_000,
    },
    async (url, options) => {
      requests.push([String(url), options]);
      if (String(url).endsWith("/api/login")) {
        return new Response(JSON.stringify({
          res: true,
          access_token: "token-1",
        }), { status: 200 });
      }
      return new Response(zlib.gzipSync(Buffer.from(JSON.stringify([{
        filename: "OR-01_260723_100000.vital",
        filesize: 123,
        dtstart: 1,
        dtend: 2,
        dtupload: 3,
      }]))), { status: 200 });
    },
  );

  const evidence = await adapter.find("OR-01_260723_100000.vital");

  assert.deepStrictEqual(evidence, {
    filename: "OR-01_260723_100000.vital",
    sizeBytes: 123,
    recordingStartedAt: 1,
    recordingEndedAt: 2,
    uploadedAt: 3,
  });
  assert.strictEqual(requests.length, 2);
});

test("VitalServer file index adapter preserves an empty index", async () => {
  const adapter = createVitalServerFileIndex(
    {
      baseUrl: "http://app",
      adminPassword: "secret",
      timeoutMs: 1_000,
    },
    async (url) => (
      String(url).endsWith("/api/login")
        ? new Response(JSON.stringify({
            res: true,
            access_token: "token-1",
          }), { status: 200 })
        : new Response(JSON.stringify({ message: "No result found" }), {
            status: 404,
          })
    ),
  );

  assert.strictEqual(await adapter.find("missing.vital"), null);
});

test("VitalServer file index adapter rejects malformed index metadata", async () => {
  const adapter = createVitalServerFileIndex(
    {
      baseUrl: "http://app",
      adminPassword: "secret",
      timeoutMs: 1_000,
    },
    async (url) => (
      String(url).endsWith("/api/login")
        ? new Response(JSON.stringify({
            res: true,
            access_token: "token-1",
          }), { status: 200 })
        : new Response(JSON.stringify([{
            filename: "OR-01_260723_100000.vital",
            filesize: "unknown",
          }]), { status: 200 })
    ),
  );

  await assert.rejects(
    adapter.find("OR-01_260723_100000.vital"),
    /filesize is invalid/,
  );
});
