import { contextBridge, ipcRenderer } from "electron";

import type {
  RuntimeConsoleControlRequest,
  RuntimeConsoleControlResponse,
} from "@tirosh-chain/runtime-console-control-contract";

contextBridge.exposeInMainWorld("vitalServerRuntimeConsole", {
  request: (request: RuntimeConsoleControlRequest): Promise<RuntimeConsoleControlResponse> => ipcRenderer.invoke("runtime-console-control:request", request),
});

// The renderer cannot read the filesystem.  It can request exactly one native
// directory chooser; the resulting Host-local path is then validated and
// imported by Host Agent, which remains the update-bundle state owner.
contextBridge.exposeInMainWorld("vitalServerRuntimeConsoleDirectorySelector", {
  selectUpdateBundleDirectory: (): Promise<string | undefined> => ipcRenderer.invoke("runtime-console-control:select-update-bundle-directory"),
});
