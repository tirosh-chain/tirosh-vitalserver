import { app, BrowserWindow, dialog, ipcMain } from "electron";
import { join } from "node:path";

import { assertRuntimeConsoleControlRequest } from "@tirosh-chain/runtime-console-control-contract";

import {
  HostAgentLocalControlTransport,
	assertHostAgentLocalControlTransportForPlatform,
  packagedRuntimeConsoleStartupArguments,
  readHostAgentLocalControlDescriptor,
  resolveHostAgentLocalControlDescriptorPath,
} from "./host_agent_local_control_transport.js";

const controlChannel = "runtime-console-control:request";
const cancelControlChannel = "runtime-console-control:request-cancel";
const selectUpdateBundleDirectoryChannel = "runtime-console-control:select-update-bundle-directory";
let hostAgentControlTransport: HostAgentLocalControlTransport | undefined;
const pendingControlRequests = new Map<string, AbortController>();

async function createRuntimeConsoleWindow(): Promise<void> {
  const window = new BrowserWindow({
    width: 1280,
    height: 900,
    minWidth: 720,
    minHeight: 600,
    webPreferences: {
      preload: join(__dirname, "runtime-console-preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webSecurity: true,
    },
  });
  await window.loadFile(join(__dirname, "renderer", "index.html"));
}

void app.whenReady().then(async () => {
  const startupArguments = app.isPackaged
    ? packagedRuntimeConsoleStartupArguments(process.argv, process.platform)
    : process.argv;
  const descriptorPath = await resolveHostAgentLocalControlDescriptorPath(startupArguments);
	const descriptor = await readHostAgentLocalControlDescriptor(descriptorPath);
	assertHostAgentLocalControlTransportForPlatform(descriptor, process.platform);
	hostAgentControlTransport = new HostAgentLocalControlTransport(descriptor);
  ipcMain.handle(controlChannel, async (event, value: unknown) => {
    if (hostAgentControlTransport === undefined) {
      throw new Error("Host Agent control transport is not initialized");
    }
    const envelope = assertControlRequestEnvelope(value);
    const key = controlRequestKey(event.sender.id, envelope.transportRequestId);
    if (pendingControlRequests.has(key)) {
      throw new Error("Runtime Console transport request ID is already pending");
    }
    const controller = new AbortController();
    pendingControlRequests.set(key, controller);
    try {
      return await hostAgentControlTransport.request(
        assertRuntimeConsoleControlRequest(envelope.request),
        { signal: controller.signal },
      );
    } finally {
      pendingControlRequests.delete(key);
    }
  });
  ipcMain.on(cancelControlChannel, (event, value: unknown) => {
    if (typeof value !== "string" || !validTransportRequestID(value)) {
      return;
    }
    pendingControlRequests.get(controlRequestKey(event.sender.id, value))?.abort();
  });
  ipcMain.handle(selectUpdateBundleDirectoryChannel, async () => {
    const selection = await dialog.showOpenDialog({
      title: "Choose signed VitalServer release bundle directory",
      properties: ["openDirectory", "dontAddToRecent"],
    });
    if (selection.canceled) {
      return undefined;
    }
    if (selection.filePaths.length !== 1 || selection.filePaths[0] === "") {
      throw new Error("desktop update-bundle selector must return exactly one explicit directory");
    }
    return selection.filePaths[0];
  });
  await createRuntimeConsoleWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      void createRuntimeConsoleWindow();
    }
  });
}).catch((error: unknown) => {
  const message = error instanceof Error ? error.message : "unknown desktop startup failure";
  process.stderr.write(`Runtime Console desktop startup failed: ${message}\n`);
  app.exit(1);
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

function assertControlRequestEnvelope(value: unknown): {
  transportRequestId: string;
  request: unknown;
} {
  if (
    typeof value !== "object"
    || value === null
    || Array.isArray(value)
    || !("transportRequestId" in value)
    || !("request" in value)
    || typeof value.transportRequestId !== "string"
    || !validTransportRequestID(value.transportRequestId)
  ) {
    throw new Error("Runtime Console control request envelope is invalid");
  }
  return {
    transportRequestId: value.transportRequestId,
    request: value.request,
  };
}

function validTransportRequestID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u.test(value);
}

function controlRequestKey(senderID: number, transportRequestID: string): string {
  return `${senderID}:${transportRequestID}`;
}
