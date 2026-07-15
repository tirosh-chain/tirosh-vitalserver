const assert = require("node:assert/strict");
const test = require("node:test");

const {
  createRawArchiveRecoveryExecutor,
} = require("../../src/adapters/outbound/http/raw-archive-recovery-executor");

test("raw archive recovery executor reports missing endpoint explicitly", async () => {
  const executor = createRawArchiveRecoveryExecutor({
    rawArchive: {
      autoExport: {
        recoverUrl: "",
      },
    },
  });

  const result = await executor.recover({
    rawArchivePath: "/archive.jsonl",
    outputDir: "/export",
    vitalserverUrl: "http://app:80",
    endpoint: "/upload",
    timeoutMs: 1000,
    vrcode: "VR-A",
    startOffset: 0,
    endOffset: 42,
  });

  assert.deepStrictEqual(result, {
    ok: false,
    reason: "not_configured",
    message: "raw archive recovery endpoint is not configured",
  });
});

test("raw archive recovery executor posts explicit recovery request", async () => {
  const originalFetch = global.fetch;
  const calls = [];
  global.fetch = (async (url, options) => {
    calls.push({ url, options });
    return response({
      artifacts: [],
      upload: {
        totalRequests: 1,
        successfulRequests: 1,
        failedRequests: 0,
      },
    });
  }) as typeof fetch;
  try {
    const executor = createRawArchiveRecoveryExecutor({
      rawArchive: {
        autoExport: {
          recoverUrl: "http://recorder-recovery:8080/raw-archive/recover-vital",
        },
      },
    });

    const result = await executor.recover({
      rawArchivePath: "/archive.jsonl",
      outputDir: "/export",
      vitalserverUrl: "http://app:80",
      endpoint: "/upload",
      timeoutMs: 12345,
      vrcode: "VR-A",
      startOffset: 10,
      endOffset: 42,
    });

    assert.strictEqual(result.ok, true);
    assert.strictEqual(calls.length, 1);
    assert.strictEqual(calls[0].url, "http://recorder-recovery:8080/raw-archive/recover-vital");
    assert.strictEqual(calls[0].options.method, "POST");
    assert.deepStrictEqual(JSON.parse(calls[0].options.body), {
      rawArchivePath: "/archive.jsonl",
      outputDir: "/export",
      vitalserverUrl: "http://app:80",
      endpoint: "/upload",
      timeout: 12,
      skipFilenameCheck: true,
      vrcode: "VR-A",
      startOffset: 10,
      endOffset: 42,
    });
  } finally {
    global.fetch = originalFetch;
  }
});

test("raw archive recovery executor rejects malformed success response", async () => {
  const originalFetch = global.fetch;
  global.fetch = (async () => response({ ok: true })) as typeof fetch;
  try {
    const executor = createRawArchiveRecoveryExecutor({
      rawArchive: {
        autoExport: {
          recoverUrl: "http://recorder-recovery:8080/raw-archive/recover-vital",
        },
      },
    });

    const result = await executor.recover({
      rawArchivePath: "/archive.jsonl",
      outputDir: "/export",
      vitalserverUrl: "http://app:80",
      endpoint: "/upload",
      timeoutMs: 1000,
      vrcode: "VR-A",
      startOffset: 0,
      endOffset: 42,
    });

    assert.deepStrictEqual(result, {
      ok: false,
      reason: "invalid_response",
      message: "raw archive recovery response did not match the recovery result contract",
      statusCode: 200,
      response: { ok: true },
    });
  } finally {
    global.fetch = originalFetch;
  }
});

test("raw archive recovery executor reports HTTP failure body", async () => {
  const originalFetch = global.fetch;
  global.fetch = (async () => response({ detail: "upload failed" }, { status: 502 })) as typeof fetch;
  try {
    const executor = createRawArchiveRecoveryExecutor({
      rawArchive: {
        autoExport: {
          recoverUrl: "http://recorder-recovery:8080/raw-archive/recover-vital",
        },
      },
    });

    const result = await executor.recover({
      rawArchivePath: "/archive.jsonl",
      outputDir: "/export",
      vitalserverUrl: "http://app:80",
      endpoint: "/upload",
      timeoutMs: 1000,
      vrcode: "VR-A",
      startOffset: 0,
      endOffset: 42,
    });

    assert.deepStrictEqual(result, {
      ok: false,
      reason: "http_failed",
      message: "raw archive recovery failed with HTTP 502",
      statusCode: 502,
      response: { detail: "upload failed" },
    });
  } finally {
    global.fetch = originalFetch;
  }
});

function response(body: unknown, options: { status?: number } = {}): Response {
  return {
    ok: (options.status || 200) >= 200 && (options.status || 200) < 300,
    status: options.status || 200,
    async text() {
      return JSON.stringify(body);
    },
  } as Response;
}
