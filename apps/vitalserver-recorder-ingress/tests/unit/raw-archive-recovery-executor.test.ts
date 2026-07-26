const assert = require("node:assert/strict");
const test = require("node:test");

const {
  createRawArchiveExporter,
} = require("../../src/adapters/outbound/http/raw-archive-recovery-executor");

test("raw archive exporter reports missing endpoint explicitly", async () => {
  const exporter = createRawArchiveExporter({
    rawArchive: {
      autoExport: {
        exportUrl: "",
      },
    },
  });

  const result = await exporter.export({
    rawArchivePath: "/archive.jsonl",
    outputDir: "/export",
    timeoutMs: 1000,
    vrcode: "VR-A",
    startOffset: 0,
    endOffset: 42,
  });

  assert.deepStrictEqual(result, {
    ok: false,
    reason: "not_configured",
    message: "raw archive export endpoint is not configured",
  });
});

test("raw archive exporter posts explicit export-only request", async () => {
  const originalFetch = global.fetch;
  const calls = [];
  global.fetch = (async (url, options) => {
    calls.push({ url, options });
    return response(exportDocument());
  }) as typeof fetch;
  try {
    const exporter = createRawArchiveExporter({
      rawArchive: {
        autoExport: {
          exportUrl: "http://recorder-recovery:8080/raw-archive/export-vital",
        },
      },
    });

    const result = await exporter.export({
      rawArchivePath: "/archive.jsonl",
      outputDir: "/export",
      timeoutMs: 12345,
      vrcode: "VR-A",
      startOffset: 10,
      endOffset: 42,
    });

    assert.strictEqual(result.ok, true);
    assert.strictEqual(calls.length, 1);
    assert.strictEqual(calls[0].url, "http://recorder-recovery:8080/raw-archive/export-vital");
    assert.strictEqual(calls[0].options.method, "POST");
    assert.deepStrictEqual(JSON.parse(calls[0].options.body), {
      rawArchivePath: "/archive.jsonl",
      outputDir: "/export",
      vrcode: "VR-A",
      startOffset: 10,
      endOffset: 42,
    });
    assert.strictEqual(result.artifacts[0].origin, "coldPathRecovery");
  } finally {
    global.fetch = originalFetch;
  }
});

test("raw archive exporter rejects malformed success response", async () => {
  const originalFetch = global.fetch;
  global.fetch = (async () => response({ ok: true })) as typeof fetch;
  try {
    const exporter = createRawArchiveExporter({
      rawArchive: {
        autoExport: {
          exportUrl: "http://recorder-recovery:8080/raw-archive/export-vital",
        },
      },
    });

    const result = await exporter.export({
      rawArchivePath: "/archive.jsonl",
      outputDir: "/export",
      timeoutMs: 1000,
      vrcode: "VR-A",
      startOffset: 0,
      endOffset: 42,
    });

    assert.deepStrictEqual(result, {
      ok: false,
      reason: "invalid_response",
      message: "raw archive export response did not match the artifact receipt contract",
      statusCode: 200,
      response: { ok: true },
    });
  } finally {
    global.fetch = originalFetch;
  }
});

test("raw archive exporter reports HTTP failure body", async () => {
  const originalFetch = global.fetch;
  global.fetch = (async () => response({ detail: "export failed" }, { status: 502 })) as typeof fetch;
  try {
    const exporter = createRawArchiveExporter({
      rawArchive: {
        autoExport: {
          exportUrl: "http://recorder-recovery:8080/raw-archive/export-vital",
        },
      },
    });

    const result = await exporter.export({
      rawArchivePath: "/archive.jsonl",
      outputDir: "/export",
      timeoutMs: 1000,
      vrcode: "VR-A",
      startOffset: 0,
      endOffset: 42,
    });

    assert.deepStrictEqual(result, {
      ok: false,
      reason: "http_failed",
      message: "raw archive export failed with HTTP 502",
      statusCode: 502,
      response: { detail: "export failed" },
    });
  } finally {
    global.fetch = originalFetch;
  }
});

function exportDocument() {
  return {
    operation: "export",
    artifacts: [{
      artifactId: "a".repeat(64),
      origin: "coldPathRecovery",
      producer: "vitalserver-recorder-recovery",
      writerVersion: "1",
      vrcode: "VR-A",
      roomNames: ["OR-A"],
      sourceArchiveId: "/archive.jsonl",
      sourceStartOffset: 10,
      sourceEndOffset: 42,
      coverageStartedAt: 1,
      coverageEndedAt: 2,
      formatVersion: 3,
      sha256: "b".repeat(64),
      filename: "VR-A_260101_000000.vital",
      sizeBytes: 10,
      createdAt: 3,
      trackCount: 1,
    }],
  };
}

function response(body: unknown, options: { status?: number } = {}): Response {
  return {
    ok: (options.status || 200) >= 200 && (options.status || 200) < 300,
    status: options.status || 200,
    async text() {
      return JSON.stringify(body);
    },
  } as Response;
}
