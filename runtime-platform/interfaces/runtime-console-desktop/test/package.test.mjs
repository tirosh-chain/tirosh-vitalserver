import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";

import {
  assertRuntimeConsolePackageBuildHost,
  electronBuilderTargetArguments,
  parseTarget,
  runtimeConsoleArtifactReceipt,
  runtimeConsoleArtifactSpecification,
  stagedRuntimeConsolePackageManifest,
  verifyRuntimeConsoleArtifactBytes,
} from "../scripts/package.mjs";

test("desktop package accepts only an explicit target", () => {
  assert.equal(parseTarget(["--target", "macos"]), "macos");
  assert.equal(parseTarget(["--target", "windows"]), "windows");
  assert.equal(parseTarget(["--target", "linux"]), "linux");
  assert.equal(parseTarget(["--target", "linux-deb"]), "linux-deb");
  assert.equal(parseTarget(["--target", "all"]), "all");
  assert.throws(() => parseTarget([]));
  assert.throws(() => parseTarget(["--target", "freebsd"]));
  assert.throws(() => parseTarget(["--target", "macos", "--extra"]));
});

test("desktop packaging uses the product delivery architecture, never the build host architecture", () => {
  assert.deepEqual(electronBuilderTargetArguments("macos"), ["--mac", "--arm64"]);
  assert.deepEqual(electronBuilderTargetArguments("windows"), ["--win", "--x64"]);
  assert.deepEqual(electronBuilderTargetArguments("linux"), ["--linux", "AppImage", "--x64"]);
  assert.deepEqual(electronBuilderTargetArguments("linux-deb"), ["--linux", "deb", "--x64"]);
  assert.throws(() => electronBuilderTargetArguments("freebsd"));
  assertRuntimeConsolePackageBuildHost("linux-deb", "linux");
  assert.throws(() => assertRuntimeConsolePackageBuildHost("linux-deb", "darwin"), /native Linux build runner/);
});

test("desktop packaging publishes one explicit C71 artifact identity per target", () => {
  assert.deepEqual(runtimeConsoleArtifactSpecification("macos", "0.1.0"), {
    platform: "macos", kind: "dmg", fileName: "VitalServer Runtime Console-0.1.0-arm64.dmg",
  });
  assert.deepEqual(runtimeConsoleArtifactSpecification("windows", "0.1.0"), {
    platform: "windows", kind: "nsis-exe", fileName: "VitalServer Runtime Console-0.1.0-x64.exe",
  });
  assert.deepEqual(runtimeConsoleArtifactSpecification("linux", "0.1.0"), {
    platform: "linux", kind: "appimage", fileName: "VitalServer Runtime Console-0.1.0-x86_64.AppImage",
  });
  assert.deepEqual(runtimeConsoleArtifactSpecification("linux-deb", "0.1.0"), {
    platform: "linux", kind: "deb", fileName: "vitalserver-runtime-console_0.1.0_amd64.deb",
  });
  assert.deepEqual(runtimeConsoleArtifactReceipt(
    runtimeConsoleArtifactSpecification("linux", "0.1.0"),
    "0.1.0",
    "a".repeat(64),
    123,
  ), {
    schemaVersion: "v1",
    artifact: {
      platform: "linux", kind: "appimage", fileName: "VitalServer Runtime Console-0.1.0-x86_64.AppImage", sha256: "a".repeat(64), sizeBytes: 123,
    },
    runtimeConsoleVersion: "0.1.0",
    localControlBootstrapContract: { contractId: "C53", schemaVersion: "v1" },
  });
  assert.throws(() => runtimeConsoleArtifactSpecification("linux", "../0.1.0"));
  assert.throws(() => runtimeConsoleArtifactReceipt(runtimeConsoleArtifactSpecification("linux", "0.1.0"), "0.1.0", "a".repeat(63), 123));
});

test("desktop packaging verifies the bytes before it publishes a C71 receipt", () => {
  const dmg = Buffer.alloc(512);
  dmg.write("koly", 0);
  verifyRuntimeConsoleArtifactBytes(runtimeConsoleArtifactSpecification("macos", "0.1.0"), dmg);
  const exe = Buffer.alloc(128);
  exe.write("MZ", 0);
  exe.writeUInt32LE(64, 60);
  exe.write("PE\0\0", 64);
  verifyRuntimeConsoleArtifactBytes(runtimeConsoleArtifactSpecification("windows", "0.1.0"), exe);
  const appImage = Buffer.from([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0, 0x41, 0x49, 2]);
  verifyRuntimeConsoleArtifactBytes(runtimeConsoleArtifactSpecification("linux", "0.1.0"), appImage);
  const deb = Buffer.concat([
    Buffer.from("!<arch>\n"),
    arMember("debian-binary", Buffer.from("2.0\n")),
    arMember("control.tar.gz", Buffer.from("x")),
    arMember("data.tar.gz", Buffer.from("x")),
  ]);
  verifyRuntimeConsoleArtifactBytes(runtimeConsoleArtifactSpecification("linux-deb", "0.1.0"), deb);
  assert.throws(() => verifyRuntimeConsoleArtifactBytes(runtimeConsoleArtifactSpecification("linux-deb", "0.1.0"), Buffer.from("!<arch>\n__.SYMDEF")), /DEB/);
});

function arMember(name, contents) {
  const encodedName = Buffer.from(`${name}/`.padEnd(16, " "));
  const header = Buffer.concat([
    encodedName,
    Buffer.from("0".padEnd(12, " ")),
    Buffer.from("0".padEnd(6, " ")),
    Buffer.from("0".padEnd(6, " ")),
    Buffer.from("100644".padEnd(8, " ")),
    Buffer.from(String(contents.length).padEnd(10, " ")),
    Buffer.from("`\n"),
  ]);
  return Buffer.concat([header, contents, ...(contents.length % 2 ? [Buffer.from("\n")] : [])]);
}

test("desktop package stage contains only runtime metadata and the bundled main entry", () => {
  assert.deepEqual(stagedRuntimeConsolePackageManifest({
    name: "@tirosh-chain/runtime-console-desktop",
    version: "0.1.0",
    author: { name: "Tirosh Chain", email: "seungbae.ji@gmail.com" },
    homepage: "https://github.com/tirosh-chain/vitalserver-runtime-platform",
    description: "Electron desktop shell",
    dependencies: { ignored: "1.0.0" },
    scripts: { ignored: "true" },
  }), {
    name: "vitalserver-runtime-console",
    version: "0.1.0",
    private: true,
    author: { name: "Tirosh Chain", email: "seungbae.ji@gmail.com" },
    homepage: "https://github.com/tirosh-chain/vitalserver-runtime-platform",
    description: "Electron desktop shell",
    main: "dist/runtime-console-main.cjs",
    license: "Apache-2.0",
  });
  assert.throws(() => stagedRuntimeConsolePackageManifest({ version: "0.1.0" }));
  assert.throws(() => stagedRuntimeConsolePackageManifest({
    name: "@tirosh-chain/runtime-console-desktop",
    version: "0.1.0",
    author: { name: "Tirosh Chain" },
    homepage: "https://github.com/tirosh-chain/vitalserver-runtime-platform",
  }));
});

test("desktop packaging declares product icons and excludes source maps from the shipped application", async () => {
  const configuration = JSON.parse(await readFile(resolve("electron-builder.config.json"), "utf8"));
  assert.deepEqual(configuration.files, ["dist/**", "!dist/**/*.map", "package.json"]);
  assert.equal(configuration.mac.icon, "assets/runtime-console.icns");
  assert.equal(configuration.win.icon, "assets/runtime-console-512.png");
  assert.equal(configuration.linux.icon, "assets/runtime-console-512.png");
  assert.equal(configuration.linux.maintainer, "Tirosh Chain <seungbae.ji@gmail.com>");
  assert.deepEqual(configuration.linux.target, ["AppImage"]);
  assert.equal(configuration.electronVersion, "41.7.1");
  assert.equal(configuration.npmRebuild, false);
  // The Finder-visible macOS bundle must carry the product name. Windows and
  // Linux keep the stable command name that operators and desktop launchers
  // invoke; Electron Builder resolves this setting per platform.
  assert.equal(configuration.productName, "VitalServer Runtime Console");
  assert.equal(configuration.mac.executableName, "VitalServer Runtime Console");
  assert.equal(configuration.win.executableName, "vitalserver-runtime-console");
  assert.equal(configuration.linux.executableName, "vitalserver-runtime-console");
  assert.equal(configuration.directories.output, "../../.tmp/runtime-console-desktop");
  assert.equal(configuration.deb.artifactName, "vitalserver-runtime-console_${version}_${arch}.${ext}");
});
