import { contextBridge, ipcRenderer } from "electron";
import { randomUUID } from "node:crypto";

import type {
  RuntimeConsoleControlRequest,
  RuntimeConsoleControlRequestOptions,
  RuntimeConsoleControlResponse,
} from "@tirosh-chain/runtime-console-control-contract";

const controlRequestChannel = "runtime-console-control:request";
const controlRequestCancelChannel = "runtime-console-control:request-cancel";

contextBridge.exposeInMainWorld("vitalServerRuntimeConsole", {
  request: (
    request: RuntimeConsoleControlRequest,
    options?: RuntimeConsoleControlRequestOptions,
  ): Promise<RuntimeConsoleControlResponse> => {
    const transportRequestId = randomUUID();
    if (options?.signal?.aborted === true) {
      return Promise.reject(abortedControlRequestError());
    }
    const abort = (): void => {
      ipcRenderer.send(controlRequestCancelChannel, transportRequestId);
    };
    options?.signal?.addEventListener("abort", abort, { once: true });
    return ipcRenderer.invoke(controlRequestChannel, {
      transportRequestId,
      request,
    }).finally(() => {
      options?.signal?.removeEventListener("abort", abort);
    }) as Promise<RuntimeConsoleControlResponse>;
  },
});

// The renderer cannot read the filesystem.  It can request exactly one native
// directory chooser; the resulting Host-local path is then validated and
// imported by Host Agent, which remains the update-bundle state owner.
contextBridge.exposeInMainWorld("vitalServerRuntimeConsoleDirectorySelector", {
  selectUpdateBundleDirectory: (): Promise<string | undefined> => ipcRenderer.invoke("runtime-console-control:select-update-bundle-directory"),
});

function abortedControlRequestError(): Error {
  const error = new Error("Runtime Console control request was cancelled");
  error.name = "AbortError";
  return error;
}
