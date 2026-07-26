import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  HostAgentLocalControlTransport,
  assertHostAgentLocalControlTransportForPlatform,
  parseHostAgentLocalControlDescriptor,
  parseOperatorInterfaceBootstrapConfiguration,
  packagedRuntimeConsoleStartupArguments,
  readHostAgentLocalControlDescriptor,
  readOperatorInterfaceBootstrapConfiguration,
  requiredLocalControlDescriptorPath,
  resolveHostAgentLocalControlDescriptorPath,
} from "../dist/host-agent-local-control-transport.mjs";

async function withControlServer(handler, action) {
  const directory = await mkdtemp(join(tmpdir(), "vitalserver-console-"));
  const socketPath = join(directory, "host-agent.sock");
  const server = createServer(handler);
  await new Promise((resolve) => server.listen(socketPath, resolve));
  try {
    await action(socketPath, directory);
  } finally {
    await new Promise((resolve, reject) => server.close((error) => error === undefined ? resolve() : reject(error)));
    await rm(directory, { recursive: true, force: true });
  }
}

test("desktop transport maps a named public read and preserves a typed non-success response", async () => {
  await withControlServer((request, response) => {
    assert.equal(request.method, "GET");
    assert.equal(request.url, "/v1/runtime/readiness");
    response.writeHead(503, { "Content-Type": "application/json" });
    response.end(JSON.stringify({ schemaVersion: "v1", state: "unavailable", issue: { code: "guest-unavailable" } }));
  }, async (socketPath) => {
    const transport = new HostAgentLocalControlTransport({ schemaVersion: "v1", transport: "unix-domain-socket", address: socketPath });
    const response = await transport.request({ kind: "read", resource: "runtime-readiness" });
    assert.equal(response.httpStatus, 503);
    assert.deepEqual(response.document, { schemaVersion: "v1", state: "unavailable", issue: { code: "guest-unavailable" } });
  });
});

test("desktop transport accepts only exact public C52 local endpoints", () => {
  for (const descriptor of [
    { schemaVersion: "v1", transport: "unix-domain-socket", address: "relative.sock" },
    { schemaVersion: "v1", transport: "unix-domain-socket", address: "/tmp/../host-agent.sock" },
    { schemaVersion: "v1", transport: "windows-named-pipe", address: "\\\\server\\pipe\\host-agent" },
    { schemaVersion: "v1", transport: "remote-http", address: "http://192.0.2.20:18280" },
    { schemaVersion: "v1", transport: "unix-domain-socket", address: "/tmp/host-agent.sock", unexpected: true },
  ]) {
    assert.throws(() => parseHostAgentLocalControlDescriptor(descriptor));
  }
});

test("desktop rejects a C52 transport belonging to another operating system", () => {
  const unix = { schemaVersion: "v1", transport: "unix-domain-socket", address: "/tmp/host-agent.sock" };
  const pipe = { schemaVersion: "v1", transport: "windows-named-pipe", address: "\\\\.\\pipe\\vitalserver-host-agent" };
  assert.doesNotThrow(() => assertHostAgentLocalControlTransportForPlatform(unix, "darwin"));
  assert.doesNotThrow(() => assertHostAgentLocalControlTransportForPlatform(unix, "linux"));
  assert.doesNotThrow(() => assertHostAgentLocalControlTransportForPlatform(pipe, "win32"));
  assert.throws(() => assertHostAgentLocalControlTransportForPlatform(unix, "win32"));
  assert.throws(() => assertHostAgentLocalControlTransportForPlatform(pipe, "darwin"));
  assert.throws(() => assertHostAgentLocalControlTransportForPlatform(unix, "freebsd"));
});

test("desktop direct-development path reads an explicit C52 descriptor", async () => {
  await withControlServer(() => undefined, async (socketPath, directory) => {
    const descriptorPath = join(directory, "host-agent.local.json");
    await writeFile(descriptorPath, JSON.stringify({ schemaVersion: "v1", transport: "unix-domain-socket", address: socketPath }), { mode: 0o644 });
    assert.equal(requiredLocalControlDescriptorPath(["electron", "runtime-console", "--local-control-descriptor", descriptorPath]), descriptorPath);
    assert.equal(await resolveHostAgentLocalControlDescriptorPath(["electron", "runtime-console", "--local-control-descriptor", descriptorPath]), descriptorPath);
    await assert.doesNotReject(readHostAgentLocalControlDescriptor(descriptorPath));
  });
});

test("desktop packaged path receives C52 only through exact C53 bootstrap configuration", async () => {
  await withControlServer(() => undefined, async (socketPath, directory) => {
    const descriptorPath = join(directory, "host-agent.local.json");
    const bootstrapPath = join(directory, "runtime-console-bootstrap.json");
    await writeFile(descriptorPath, JSON.stringify({ schemaVersion: "v1", transport: "unix-domain-socket", address: socketPath }), { mode: 0o644 });
    await writeFile(bootstrapPath, JSON.stringify({ schemaVersion: "v1", bootstrapConfigurationPath: bootstrapPath, localAdministrationDescriptorPath: descriptorPath }), { mode: 0o644 });
    assert.deepEqual(await readOperatorInterfaceBootstrapConfiguration(bootstrapPath), { schemaVersion: "v1", bootstrapConfigurationPath: bootstrapPath, localAdministrationDescriptorPath: descriptorPath });
    assert.equal(await resolveHostAgentLocalControlDescriptorPath(["electron", "runtime-console", "--operator-interface-bootstrap", bootstrapPath]), descriptorPath);
    assert.throws(() => requiredLocalControlDescriptorPath(["electron", "runtime-console", "--operator-interface-bootstrap", bootstrapPath]));
    assert.throws(() => parseOperatorInterfaceBootstrapConfiguration({ schemaVersion: "v1", bootstrapConfigurationPath: bootstrapPath, localAdministrationDescriptorPath: "https://operator.example.test:18280" }));
    assert.throws(() => parseOperatorInterfaceBootstrapConfiguration({ schemaVersion: "v1", bootstrapConfigurationPath: bootstrapPath, localAdministrationDescriptorPath: descriptorPath, unexpected: true }));
  });
});

test("desktop startup rejects absent or ambiguous endpoint configuration", async () => {
  assert.throws(() => requiredLocalControlDescriptorPath(["electron", "runtime-console"]));
  await assert.rejects(resolveHostAgentLocalControlDescriptorPath(["electron", "runtime-console"]));
  await assert.rejects(resolveHostAgentLocalControlDescriptorPath([
    "electron",
    "runtime-console",
    "--local-control-descriptor",
    "/tmp/control.json",
    "--operator-interface-bootstrap",
    "/tmp/bootstrap.json",
  ]));
});

test("packaged desktop has one reviewed C53 location per supported operating system", () => {
  assert.deepEqual(packagedRuntimeConsoleStartupArguments(["runtime-console"], "darwin"), [
    "runtime-console",
    "--operator-interface-bootstrap",
    "/Library/Application Support/VitalServerRuntimePlatform/control/runtime-console-bootstrap.json",
  ]);
  assert.deepEqual(packagedRuntimeConsoleStartupArguments(["runtime-console"], "win32"), [
    "runtime-console",
    "--operator-interface-bootstrap",
    "C:\\ProgramData\\VitalServerRuntimePlatform\\control\\runtime-console-bootstrap.json",
  ]);
  assert.deepEqual(packagedRuntimeConsoleStartupArguments(["runtime-console"], "linux"), [
    "runtime-console",
    "--operator-interface-bootstrap",
    "/opt/vitalserver-runtime-platform/control/runtime-console-bootstrap.json",
  ]);
  assert.throws(() => packagedRuntimeConsoleStartupArguments(["runtime-console"], "freebsd"));
});
