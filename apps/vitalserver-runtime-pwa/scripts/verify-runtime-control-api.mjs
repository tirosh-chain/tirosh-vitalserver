import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const pwaRoot = path.resolve(scriptDir, "..");
const repoRoot = path.resolve(pwaRoot, "..", "..");
const openapiPath = path.join(repoRoot, "docs", "runtime", "runtime-control.openapi.json");
const generatedPath = path.join(
  pwaRoot,
  "src",
  "domain",
  "runtime-control",
  "contracts",
  "generated",
  "runtime-control.ts"
);
const openapiTypescript = path.join(pwaRoot, "node_modules", ".bin", "openapi-typescript");
const tempDir = mkdtempSync(path.join(tmpdir(), "vitalserver-runtime-control-api-"));
const tempGeneratedPath = path.join(tempDir, "runtime-control.ts");

try {
  const result = spawnSync(
    openapiTypescript,
    [openapiPath, "-o", tempGeneratedPath],
    { cwd: pwaRoot, stdio: "inherit" }
  );
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }

  const expected = readFileSync(tempGeneratedPath, "utf8");
  const actual = readFileSync(generatedPath, "utf8");
  if (actual !== expected) {
    console.error("Runtime Control OpenAPI generated PWA contract is out of sync.");
    console.error("Run `make pwa/generate-api`, review the generated diff, and commit it.");
    process.exit(1);
  }

  console.log("Runtime Control OpenAPI generated PWA contract is up to date.");
} finally {
  rmSync(tempDir, { recursive: true, force: true });
}
