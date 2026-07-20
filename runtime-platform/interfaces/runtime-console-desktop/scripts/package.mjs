import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { cp, lstat, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const desktopRoot = resolve(dirname(scriptPath), "..");
const interfacesRoot = resolve(desktopRoot, "..");
const packageConfigurationPath = join(desktopRoot, "electron-builder.config.json");
const runtimeConsoleSourcePackageName = "@tirosh-chain/runtime-console-desktop";
const runtimeConsoleProductPackageName = "vitalserver-runtime-console";
const runtimeConsoleArtifactReceiptSuffix = ".runtime-console-artifact-receipt.json";
const macosOperatorApplicationBundleName = "VitalServer Runtime Platform.app";

/**
 * C71 is the Runtime Console packager's immutable output description.  A
 * release composer receives it together with the actual bytes; it never has
 * to infer a target from the build host or an Electron Builder output name.
 */
export function runtimeConsoleArtifactSpecification(targetValue, version) {
  if (!isSafeArtifactVersion(version)) {
    throw new Error("Runtime Console artifact version must be a non-empty safe package version");
  }
  if (targetValue === "macos") {
    return { platform: "macos", kind: "dmg", fileName: `VitalServer Runtime Console-${version}-arm64.dmg` };
  }
  if (targetValue === "windows") {
    return { platform: "windows", kind: "nsis-exe", fileName: `VitalServer Runtime Console-${version}-x64.exe` };
  }
  if (targetValue === "linux") {
    return { platform: "linux", kind: "appimage", fileName: `VitalServer Runtime Console-${version}-x86_64.AppImage` };
  }
  if (targetValue === "linux-deb") {
    return { platform: "linux", kind: "deb", fileName: `vitalserver-runtime-console_${version}_amd64.deb` };
  }
  throw new Error("Runtime Console artifact target must be macos, windows, linux, or linux-deb");
}

export function runtimeConsoleArtifactReceipt(specification, version, sha256, sizeBytes) {
  if (!isRuntimeConsoleArtifactSpecification(specification) || !isSafeArtifactVersion(version) || !/^[a-f0-9]{64}$/.test(sha256) || !Number.isSafeInteger(sizeBytes) || sizeBytes < 1) {
    throw new Error("Runtime Console artifact receipt requires one verified package artifact");
  }
  return {
    schemaVersion: "v1",
    artifact: { ...specification, sha256, sizeBytes },
    runtimeConsoleVersion: version,
    localControlBootstrapContract: {
      contractId: "C53",
      schemaVersion: "v1",
    },
  };
}

/**
 * Confirm the output is structurally the artifact C71 claims it to be.
 *
 * Electron Builder can exit successfully even when a cross-host packager has
 * emitted an unrelated archive at the requested `.deb` path. A filename,
 * regular-file check, and hash would turn that failure into a trusted release
 * receipt. This deliberately performs only portable, format-level checks;
 * native install/launch evidence remains a platform acceptance concern.
 */
export function verifyRuntimeConsoleArtifactBytes(specification, artifactBytes) {
  if (!isRuntimeConsoleArtifactSpecification(specification) || !Buffer.isBuffer(artifactBytes) || artifactBytes.length < 4) {
    throw new Error("Runtime Console artifact verification requires one artifact specification and non-empty bytes");
  }
  if (specification.kind === "dmg") {
    if (artifactBytes.length < 512 || !artifactBytes.subarray(-512, -508).equals(Buffer.from("koly"))) {
      throw new Error("Runtime Console DMG does not contain a UDIF koly footer");
    }
    return;
  }
  if (specification.kind === "nsis-exe") {
    if (!artifactBytes.subarray(0, 2).equals(Buffer.from("MZ")) || artifactBytes.length < 64) {
      throw new Error("Runtime Console Windows artifact is not a PE executable");
    }
    const headerOffset = artifactBytes.readUInt32LE(60);
    if (headerOffset + 4 > artifactBytes.length || !artifactBytes.subarray(headerOffset, headerOffset + 4).equals(Buffer.from("PE\0\0"))) {
      throw new Error("Runtime Console Windows artifact has no PE header");
    }
    return;
  }
  if (specification.kind === "appimage") {
    if (artifactBytes.length < 11 || !artifactBytes.subarray(0, 4).equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46])) || !artifactBytes.subarray(8, 11).equals(Buffer.from([0x41, 0x49, 0x02]))) {
      throw new Error("Runtime Console Linux artifact is not an AppImage type 2 executable");
    }
    return;
  }
  if (specification.kind === "deb") {
    verifyDebArchive(artifactBytes);
    return;
  }
  throw new Error("Runtime Console artifact kind is unsupported");
}

if (process.argv[1] !== undefined && resolve(process.argv[1]) === scriptPath) {
  await packageRuntimeConsole(parseTarget(process.argv.slice(2)));
}

export function parseTarget(arguments_) {
  if (arguments_.length !== 2 || arguments_[0] !== "--target") {
    throw new Error("Runtime Console package requires exactly --target macos|macos-application|windows|linux|linux-deb|all");
  }
  const targetValue = arguments_[1];
  if (targetValue !== "macos" && targetValue !== "macos-application" && targetValue !== "windows" && targetValue !== "linux" && targetValue !== "linux-deb" && targetValue !== "all") {
    throw new Error("Runtime Console package target must be macos, macos-application, windows, linux, linux-deb, or all");
  }
  return targetValue;
}

/**
 * Return the reviewed product architecture for one Runtime Console installer.
 *
 * Electron Builder otherwise selects the architecture of the build machine.
 * That is a build-host fact, not release intent: a macOS arm64 worker must
 * not silently turn the Windows/Linux product artifacts into arm64 builds.
 * The product delivery matrix currently selects macOS arm64 and Windows/Linux
 * amd64, so this mapping is intentionally explicit at the packaging boundary.
 */
export function electronBuilderTargetArguments(targetValue) {
  if (targetValue === "macos") {
    return ["--mac", "--arm64"];
  }
  if (targetValue === "macos-application") {
    return ["--mac", "--arm64", "--dir"];
  }
  if (targetValue === "windows") {
    return ["--win", "--x64"];
  }
  if (targetValue === "linux") {
    return ["--linux", "AppImage", "--x64"];
  }
  if (targetValue === "linux-deb") {
    return ["--linux", "deb", "--x64"];
  }
  if (targetValue === "all") {
    return ["--mac", "--arm64", "--win", "--x64", "--linux", "AppImage", "--x64"];
  }
  throw new Error("Runtime Console package target must be macos, macos-application, windows, linux, linux-deb, or all");
}

/** A DEB is a Linux package-manager artifact, so its builder is Linux-only. */
export function assertRuntimeConsolePackageBuildHost(targetValue, hostPlatform = process.platform) {
  if (targetValue === "linux-deb" && hostPlatform !== "linux") {
    throw new Error("Runtime Console Linux DEB packaging requires a native Linux build runner; use the AppImage target for the portable Linux artifact");
  }
}

export function stagedRuntimeConsolePackageManifest(sourcePackage) {
  if (!isRecord(sourcePackage) || sourcePackage.name !== runtimeConsoleSourcePackageName || typeof sourcePackage.version !== "string") {
    throw new Error(`Runtime Console desktop package metadata requires source package ${runtimeConsoleSourcePackageName} and a version`);
  }
  if (!isAuthor(sourcePackage.author) || typeof sourcePackage.homepage !== "string" || sourcePackage.homepage === "") {
    throw new Error("Runtime Console desktop package metadata requires an explicit author and homepage");
  }
  return {
    name: runtimeConsoleProductPackageName,
    version: sourcePackage.version,
    private: true,
    author: sourcePackage.author,
    homepage: sourcePackage.homepage,
    description: typeof sourcePackage.description === "string" ? sourcePackage.description : "VitalServer Runtime Console",
    main: "dist/runtime-console-main.cjs",
    license: "Apache-2.0",
  };
}

export async function packageRuntimeConsole(targetValue) {
  assertRuntimeConsolePackageBuildHost(targetValue);
  const desktopPackage = JSON.parse(await readFile(join(desktopRoot, "package.json"), "utf8"));
  if (targetValue === "macos-application") {
    await packageMacOSOperatorApplication();
    return;
  }
  await invalidateRuntimeConsoleArtifactReceipts(targetValue, desktopPackage.version);
  const stage = await mkdtemp(join(tmpdir(), "vitalserver-runtime-console-package-"));
  try {
    await cp(join(desktopRoot, "dist"), join(stage, "dist"), { recursive: true, force: false, errorOnExist: true });
    await writeFile(join(stage, "package.json"), `${JSON.stringify(stagedRuntimeConsolePackageManifest(desktopPackage), null, 2)}\n`, "utf8");
    await runElectronBuilder(targetValue, stage);
    await publishRuntimeConsoleArtifactReceipts(targetValue, desktopPackage.version);
  } finally {
    await rm(stage, { recursive: true, force: true });
  }
}

/**
 * Build the exact `.app` tree selected by the macOS product PKG composer.
 * This is a build input, not a second operator-delivered installer.  The C47
 * release declaration selects the copied app tree and C48 later records its
 * package-visible identity.
 */
export async function packageMacOSOperatorApplication() {
  const stage = await mkdtemp(join(tmpdir(), "vitalserver-runtime-platform-application-"));
  const applicationPath = join(desktopRoot, "..", "..", ".tmp", "runtime-console-desktop", "mac-arm64", macosOperatorApplicationBundleName);
  try {
    await rm(applicationPath, { recursive: true, force: true });
    await cp(join(desktopRoot, "dist"), join(stage, "dist"), { recursive: true, force: false, errorOnExist: true });
    const desktopPackage = JSON.parse(await readFile(join(desktopRoot, "package.json"), "utf8"));
    await writeFile(join(stage, "package.json"), `${JSON.stringify(stagedRuntimeConsolePackageManifest(desktopPackage), null, 2)}\n`, "utf8");
    await runElectronBuilder("macos-application", stage);
    const information = await lstat(applicationPath);
    if (!information.isDirectory() || information.isSymbolicLink()) {
      throw new Error(`Runtime Platform application output is not one directory: ${applicationPath}`);
    }
  } finally {
    await rm(stage, { recursive: true, force: true });
  }
}

async function invalidateRuntimeConsoleArtifactReceipts(targetValue, version) {
  for (const artifactTarget of artifactTargetsForPackaging(targetValue)) {
    const specification = runtimeConsoleArtifactSpecification(artifactTarget, version);
    const artifactPath = join(desktopRoot, "..", "..", ".tmp", "runtime-console-desktop", specification.fileName);
    await rm(`${artifactPath}${runtimeConsoleArtifactReceiptSuffix}`, { force: true });
  }
}

async function publishRuntimeConsoleArtifactReceipts(targetValue, version) {
  for (const artifactTarget of artifactTargetsForPackaging(targetValue)) {
    const specification = runtimeConsoleArtifactSpecification(artifactTarget, version);
    const artifactPath = join(desktopRoot, "..", "..", ".tmp", "runtime-console-desktop", specification.fileName);
    const information = await lstat(artifactPath);
    if (!information.isFile() || information.isSymbolicLink() || information.size < 1) {
      throw new Error(`Runtime Console package output is not one regular artifact: ${artifactPath}`);
    }
    const artifactBytes = await readFile(artifactPath);
    verifyRuntimeConsoleArtifactBytes(specification, artifactBytes);
    const sha256 = createHash("sha256").update(artifactBytes).digest("hex");
    const receipt = runtimeConsoleArtifactReceipt(specification, version, sha256, information.size);
    await writeFile(`${artifactPath}${runtimeConsoleArtifactReceiptSuffix}`, `${JSON.stringify(receipt, null, 2)}\n`, "utf8");
  }
}

function verifyDebArchive(artifactBytes) {
  if (!artifactBytes.subarray(0, 8).equals(Buffer.from("!<arch>\n"))) {
    throw new Error("Runtime Console DEB is not an ar archive");
  }
  let offset = 8;
  const entries = new Map();
  while (offset < artifactBytes.length) {
    if (offset + 60 > artifactBytes.length) {
      throw new Error("Runtime Console DEB has a truncated ar member header");
    }
    const header = artifactBytes.subarray(offset, offset + 60);
    if (!header.subarray(58, 60).equals(Buffer.from("`\n"))) {
      throw new Error("Runtime Console DEB has an invalid ar member trailer");
    }
    const name = header.subarray(0, 16).toString("ascii").trim().replace(/\/$/, "");
    const sizeText = header.subarray(48, 58).toString("ascii").trim();
    if (!/^[0-9]+$/.test(sizeText)) {
      throw new Error("Runtime Console DEB has an invalid ar member size");
    }
    const size = Number(sizeText);
    const contentStart = offset + 60;
    const contentEnd = contentStart + size;
    if (!Number.isSafeInteger(size) || contentEnd > artifactBytes.length) {
      throw new Error("Runtime Console DEB has a truncated ar member");
    }
    entries.set(name, artifactBytes.subarray(contentStart, contentEnd));
    offset = contentEnd + (size % 2);
  }
  const debianBinary = entries.get("debian-binary");
  if (debianBinary === undefined || !debianBinary.equals(Buffer.from("2.0\n"))) {
    throw new Error("Runtime Console DEB has no debian-binary 2.0 member");
  }
  const names = [...entries.keys()];
  if (!names.some((name) => /^control\.tar\.(gz|xz|zst)$/.test(name)) || !names.some((name) => /^data\.tar\.(gz|xz|zst)$/.test(name))) {
    throw new Error("Runtime Console DEB has no control and data archive members");
  }
}

function artifactTargetsForPackaging(targetValue) {
  if (targetValue === "all") {
    return ["macos", "windows", "linux"];
  }
  return [targetValue];
}

async function runElectronBuilder(targetValue, stage) {
  const executable = process.platform === "win32"
    ? join(interfacesRoot, "node_modules", ".bin", "electron-builder.cmd")
    : join(interfacesRoot, "node_modules", ".bin", "electron-builder");
  const builderArguments = [
    "--projectDir", desktopRoot,
    "--config", packageConfigurationPath,
    `--config.directories.app=${stage}`,
    ...electronBuilderTargetArguments(targetValue),
    "--publish", "never",
  ];
  if (targetValue === "macos-application") {
    builderArguments.push(
      "--config.productName=VitalServer Runtime Platform",
      "--config.mac.executableName=VitalServer Runtime Platform",
    );
  }
  await run(executable, builderArguments);
}

function run(command, arguments_) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, arguments_, { cwd: desktopRoot, stdio: "inherit" });
    child.once("error", reject);
    child.once("exit", (code, signal) => {
      if (code === 0) {
        resolvePromise();
        return;
      }
      reject(new Error(`electron-builder exited with code ${code ?? "none"}${signal === null ? "" : ` and signal ${signal}`}`));
    });
  });
}

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isAuthor(value) {
  return isRecord(value) && typeof value.name === "string" && value.name !== "" && typeof value.email === "string" && value.email !== "";
}

function isSafeArtifactVersion(value) {
  return typeof value === "string" && /^[0-9A-Za-z][0-9A-Za-z.+-]{0,127}$/.test(value);
}

function isRuntimeConsoleArtifactSpecification(value) {
  return isRecord(value)
    && (value.platform === "macos" || value.platform === "windows" || value.platform === "linux")
    && (value.kind === "dmg" || value.kind === "nsis-exe" || value.kind === "appimage" || value.kind === "deb")
    && typeof value.fileName === "string"
    && value.fileName !== ""
    && !value.fileName.includes("/")
    && !value.fileName.includes("\\\\");
}
