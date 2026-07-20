import { lstat, readFile } from "node:fs/promises";
import { request as requestHTTP } from "node:http";

import {
  composeHostAgentControlHTTPRequest,
  type RuntimeConsoleControlRequest,
  type RuntimeConsoleControlResponse,
  type RuntimeConsoleControlTransport,
} from "@tirosh-chain/runtime-console-control-contract";

const maximumControlResponseBytes = 4 * 1024 * 1024;
const maximumDescriptorBytes = 16 * 1024;
const packagedRuntimeConsoleBootstrapPaths: Readonly<Record<"darwin" | "win32" | "linux", string>> = {
  darwin: "/Library/Application Support/VitalServerRuntimePlatform/control/runtime-console-bootstrap.json",
  win32: "C:\\ProgramData\\VitalServerRuntimePlatform\\control\\runtime-console-bootstrap.json",
  // C53 is part of the immutable Host package payload on Linux.  The DEB
  // composer installs it below /opt alongside the active Host release; using
  // /var/lib here would make a successfully installed Console look for a
  // second, undeclared bootstrap file.
  linux: "/opt/vitalserver-runtime-platform/control/runtime-console-bootstrap.json",
};

export type HostAgentLocalControlDescriptor = {
  readonly schemaVersion: "v1";
  readonly transport: "unix-domain-socket" | "windows-named-pipe";
  readonly address: string;
};

/**
 * OperatorInterfaceBootstrapConfiguration is the desktop consumer's narrow
 * view of C53. Host installation owns this configuration; it identifies the
 * Host Agent-published C52 descriptor but cannot select a remote endpoint,
 * authorization policy, or Host deployment configuration.
 */
export type OperatorInterfaceBootstrapConfiguration = {
  readonly schemaVersion: "v1";
  readonly bootstrapConfigurationPath: string;
  readonly localAdministrationDescriptorPath: string;
};

/**
 * HostAgentLocalControlTransport is the desktop-main-process adapter for the
 * Host-owned C52 descriptor. It opens neither a remote HTTP connection nor an
 * arbitrary renderer-provided endpoint. OS authorization is enforced by the
 * Host listener before this HTTP facade receives a request.
 */
export class HostAgentLocalControlTransport implements RuntimeConsoleControlTransport {
  public constructor(private readonly endpoint: HostAgentLocalControlDescriptor) {}

  public async request(controlRequest: RuntimeConsoleControlRequest): Promise<RuntimeConsoleControlResponse> {
    const request = composeHostAgentControlHTTPRequest(controlRequest);
    const encodedBody = request.body === undefined ? undefined : JSON.stringify(request.body);
    return new Promise<RuntimeConsoleControlResponse>((resolve, reject) => {
      const pending = requestHTTP({
        protocol: "http:",
        hostname: "host-agent.local",
        method: request.method,
        path: request.path,
        socketPath: this.endpoint.address,
        headers: {
          Accept: "application/json",
          ...(encodedBody === undefined ? {} : { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(encodedBody) }),
        },
      }, (response) => {
        const chunks: Buffer[] = [];
        let size = 0;
        response.on("data", (chunk: Buffer) => {
          size += chunk.length;
          if (size > maximumControlResponseBytes) {
            response.destroy(new Error("Host Agent local control response exceeds 4 MiB limit"));
            return;
          }
          chunks.push(chunk);
        });
        response.on("error", reject);
        response.on("end", () => {
          try {
            const encodedDocument = Buffer.concat(chunks).toString("utf8");
            const document: unknown = JSON.parse(encodedDocument);
            resolve({ httpStatus: response.statusCode ?? 0, document });
          } catch (error: unknown) {
            reject(asError(error, "Host Agent local control response is not valid JSON"));
          }
        });
      });
      pending.setTimeout(10_000, () => pending.destroy(new Error("Host Agent local control request timed out")));
      pending.on("error", reject);
      if (encodedBody !== undefined) {
        pending.write(encodedBody);
      }
      pending.end();
    });
  }
}

/**
 * readHostAgentLocalControlDescriptor accepts exactly one Host-published C52
 * descriptor. Descriptor absence, a symbolic link, invalid JSON, or an
 * unsupported transport remains a desktop startup failure; none becomes a
 * loopback port or a remote fallback.
 */
export async function readHostAgentLocalControlDescriptor(path: string): Promise<HostAgentLocalControlDescriptor> {
  const encoded = await readExactRegularJSONFile(path, "Host Agent local control descriptor");
  let value: unknown;
  try {
    value = JSON.parse(encoded);
  } catch (error: unknown) {
    throw asError(error, "Host Agent local control descriptor is not valid JSON");
  }
  return parseHostAgentLocalControlDescriptor(value);
}

/**
 * readOperatorInterfaceBootstrapConfiguration reads an explicit C53 document
 * that a reviewed OS launcher supplied. Absence or invalid content remains a
 * startup failure. It never discovers C33, a port, an environment endpoint,
 * or another local path.
 */
export async function readOperatorInterfaceBootstrapConfiguration(path: string): Promise<OperatorInterfaceBootstrapConfiguration> {
  const encoded = await readExactRegularJSONFile(path, "Runtime Console bootstrap configuration");
  let value: unknown;
  try {
    value = JSON.parse(encoded);
  } catch (error: unknown) {
    throw asError(error, "Runtime Console bootstrap configuration is not valid JSON");
  }
  const configuration = parseOperatorInterfaceBootstrapConfiguration(value);
  if (configuration.bootstrapConfigurationPath !== path) {
    throw new Error("C53 bootstrapConfigurationPath does not match the explicit desktop startup path");
  }
  return configuration;
}

export function parseHostAgentLocalControlDescriptor(value: unknown): HostAgentLocalControlDescriptor {
  if (!isRecord(value) || !hasOnlyKeys(value, ["schemaVersion", "transport", "address"]) || value.schemaVersion !== "v1") {
    throw new Error("Host Agent local control descriptor must be an exact C52 v1 document");
  }
  if (value.transport === "unix-domain-socket") {
    if (!isSafeUnixSocketAddress(value.address)) {
      throw new Error("C52 Unix socket address must be an absolute non-traversing path");
    }
    return { schemaVersion: "v1", transport: value.transport, address: value.address };
  }
  if (value.transport === "windows-named-pipe") {
    if (!isWindowsNamedPipeAddress(value.address)) {
      throw new Error("C52 Windows named-pipe address is invalid");
    }
    return { schemaVersion: "v1", transport: value.transport, address: value.address };
  }
  throw new Error("C52 local administration transport is not supported");
}

/**
 * assertHostAgentLocalControlTransportForPlatform prevents a packaged shell
 * from treating another operating system's C52 as an interchangeable local
 * address. C52 is explicit state: a Windows named pipe is not a Unix socket,
 * and an unsupported Host OS has no local-control fallback.
 */
export function assertHostAgentLocalControlTransportForPlatform(
  descriptor: HostAgentLocalControlDescriptor,
  platform: NodeJS.Platform,
): void {
  if (platform === "win32" && descriptor.transport === "windows-named-pipe") {
    return;
  }
  if ((platform === "darwin" || platform === "linux") && descriptor.transport === "unix-domain-socket") {
    return;
  }
  if (platform !== "win32" && platform !== "darwin" && platform !== "linux") {
    throw new Error(`Runtime Console has no C52 local-control transport for platform ${platform}`);
  }
  throw new Error(`C52 transport ${descriptor.transport} is not supported by Runtime Console on ${platform}`);
}

export function parseOperatorInterfaceBootstrapConfiguration(value: unknown): OperatorInterfaceBootstrapConfiguration {
  if (!isRecord(value) || !hasOnlyKeys(value, ["schemaVersion", "bootstrapConfigurationPath", "localAdministrationDescriptorPath"]) || value.schemaVersion !== "v1") {
    throw new Error("Runtime Console bootstrap configuration must be an exact C53 v1 document");
  }
  if (!isSafeHostAbsolutePath(value.bootstrapConfigurationPath) || !isSafeHostAbsolutePath(value.localAdministrationDescriptorPath)) {
    throw new Error("C53 paths must be absolute non-traversing host paths");
  }
  return {
    schemaVersion: "v1",
    bootstrapConfigurationPath: value.bootstrapConfigurationPath,
    localAdministrationDescriptorPath: value.localAdministrationDescriptorPath,
  };
}

export function requiredLocalControlDescriptorPath(arguments_: readonly string[]): string {
  const values = desktopBootstrapArguments(arguments_);
  if (values.operatorInterfaceBootstrapPath !== undefined) {
    throw new Error("--local-control-descriptor cannot be combined with --operator-interface-bootstrap");
  }
  if (values.localControlDescriptorPath === undefined) {
    throw new Error("--local-control-descriptor is required; desktop console does not discover Host Agent deployment input or use an environment endpoint");
  }
  return values.localControlDescriptorPath;
}

/**
 * resolveHostAgentLocalControlDescriptorPath accepts one deliberate startup
 * route: a development C52 path or an installer-owned C53 bootstrap path.
 * The packaged launcher uses C53; the direct C52 option remains useful for
 * focused development only. They are mutually exclusive, so one source owns
 * every startup path.
 */
export async function resolveHostAgentLocalControlDescriptorPath(arguments_: readonly string[]): Promise<string> {
  const values = desktopBootstrapArguments(arguments_);
  if (values.localControlDescriptorPath !== undefined && values.operatorInterfaceBootstrapPath !== undefined) {
    throw new Error("--local-control-descriptor and --operator-interface-bootstrap are mutually exclusive");
  }
  if (values.localControlDescriptorPath !== undefined) {
    return values.localControlDescriptorPath;
  }
  if (values.operatorInterfaceBootstrapPath !== undefined) {
    const configuration = await readOperatorInterfaceBootstrapConfiguration(values.operatorInterfaceBootstrapPath);
    return configuration.localAdministrationDescriptorPath;
  }
  throw new Error("one explicit --local-control-descriptor or --operator-interface-bootstrap path is required; desktop console does not discover Host Agent deployment input or use an environment endpoint");
}

/**
 * packagedRuntimeConsoleStartupArguments supplies the one installation-owned
 * C53 location selected by the OS product package. This is a fixed product
 * integration contract, not endpoint discovery: unsupported platforms fail,
 * and the C53/C52 files are still strictly decoded afterwards.
 */
export function packagedRuntimeConsoleStartupArguments(
  processArguments: readonly string[],
  platform: NodeJS.Platform,
): readonly string[] {
  const bootstrapPath = packagedRuntimeConsoleBootstrapPaths[platform as keyof typeof packagedRuntimeConsoleBootstrapPaths];
  if (bootstrapPath === undefined) {
    throw new Error(`Runtime Console has no packaged C53 bootstrap path for platform ${platform}`);
  }
  return [processArguments[0] ?? "runtime-console", "--operator-interface-bootstrap", bootstrapPath];
}

function desktopBootstrapArguments(arguments_: readonly string[]): {
  readonly localControlDescriptorPath: string | undefined;
  readonly operatorInterfaceBootstrapPath: string | undefined;
} {
  let descriptorPath: string | undefined;
  let bootstrapPath: string | undefined;
  for (let index = 0; index < arguments_.length; index += 1) {
    const option = arguments_[index];
    if (option !== "--local-control-descriptor" && option !== "--operator-interface-bootstrap") {
      continue;
    }
    const candidate = arguments_[index + 1];
    if (candidate === undefined || candidate === "") {
      throw new Error(`${option} must occur exactly once with one path`);
    }
    if (option === "--local-control-descriptor") {
      if (descriptorPath !== undefined) {
        throw new Error("--local-control-descriptor must occur exactly once with one path");
      }
      descriptorPath = candidate;
    } else {
      if (bootstrapPath !== undefined) {
        throw new Error("--operator-interface-bootstrap must occur exactly once with one path");
      }
      bootstrapPath = candidate;
    }
    index += 1;
  }
  if (descriptorPath !== undefined) {
    assertSafeHostAbsolutePath(descriptorPath, "Host Agent local control descriptor path");
  }
  if (bootstrapPath !== undefined) {
    assertSafeHostAbsolutePath(bootstrapPath, "Runtime Console bootstrap configuration path");
  }
  return { localControlDescriptorPath: descriptorPath, operatorInterfaceBootstrapPath: bootstrapPath };
}

async function readExactRegularJSONFile(path: string, documentName: string): Promise<string> {
  assertSafeHostAbsolutePath(path, `${documentName} path`);
  const information = await lstat(path);
  if (!information.isFile() || information.isSymbolicLink()) {
    throw new Error(`${documentName} must be a regular non-symlink file`);
  }
  if (information.size > maximumDescriptorBytes) {
    throw new Error(`${documentName} exceeds 16 KiB limit`);
  }
  return readFile(path, "utf8");
}

function assertSafeHostAbsolutePath(path: string, label: string): void {
  if (!isSafeHostAbsolutePath(path)) {
    throw new Error(`${label} must be absolute and non-traversing`);
  }
}

function isSafeHostAbsolutePath(value: unknown): value is string {
  if (typeof value !== "string" || value === "" || value.includes("\u0000")) {
    return false;
  }
  if (value.startsWith("/")) {
    return !value.includes("\\") && !value.split("/").includes("..");
  }
  return /^[A-Za-z]:[\\\\/]/.test(value) && !value.split(/[\\\\/]/).includes("..");
}

function isSafeUnixSocketAddress(value: unknown): value is string {
  return typeof value === "string" && value.length >= 2 && value.length <= 104 && value.startsWith("/") && !value.includes("\\") && !value.split("/").includes("..");
}

function isWindowsNamedPipeAddress(value: unknown): value is string {
  return typeof value === "string" && /^\\\\\.\\pipe\\[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  const valueKeys = Object.keys(value);
  return valueKeys.length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}

function asError(value: unknown, fallback: string): Error {
  return value instanceof Error ? value : new Error(fallback);
}
