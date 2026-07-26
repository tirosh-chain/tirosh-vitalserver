import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const root = process.cwd();
const policy = await readJSON(resolve(root, "tooling/npm-license-policy.json"));
const lock = await readJSON(resolve(root, "package-lock.json"));

if (policy.schemaVersion !== "v1" || !Array.isArray(policy.allowedLicenseValues) || !Array.isArray(policy.forbiddenLicenseValues)) {
  throw new Error("npm license policy must declare schemaVersion v1 plus allowedLicenseValues and forbiddenLicenseValues arrays");
}
if (lock.lockfileVersion !== 3 || typeof lock.packages !== "object" || lock.packages === null) {
  throw new Error("npm package-lock must use lockfileVersion 3 and packages metadata");
}

const allowed = new Set(policy.allowedLicenseValues);
const forbidden = new Set(policy.forbiddenLicenseValues);
const findings = [];
let inspected = 0;

for (const [packagePath, packageMetadata] of Object.entries(lock.packages)) {
  if (!packagePath.startsWith("node_modules/")) {
    continue;
  }
  if (typeof packageMetadata !== "object" || packageMetadata === null || Array.isArray(packageMetadata)) {
    findings.push(`${packagePath}: package metadata is not an object`);
    continue;
  }
  // npm represents the three local interface workspaces as symlinks below
  // node_modules. They are first-party source, not third-party package
  // inventory, and their repository license is reviewed separately.
  if (packageMetadata.link === true) {
    continue;
  }
  const packageName = typeof packageMetadata.name === "string" ? packageMetadata.name : packagePath.slice("node_modules/".length);
  const license = packageMetadata.license;
  inspected += 1;
  if (typeof license !== "string" || license === "") {
    findings.push(`${packageName}: package-lock has no explicit license metadata`);
    continue;
  }
  if (forbidden.has(license)) {
    findings.push(`${packageName}: forbidden license ${license}`);
    continue;
  }
  if (!allowed.has(license)) {
    findings.push(`${packageName}: license ${license} is not in the explicit allowlist`);
  }
}

if (findings.length > 0) {
  throw new Error(`npm license policy failed:\n${findings.join("\n")}`);
}
process.stdout.write(`npm license policy passed for ${inspected} locked third-party packages\n`);

async function readJSON(path) {
  return JSON.parse(await readFile(path, "utf8"));
}
