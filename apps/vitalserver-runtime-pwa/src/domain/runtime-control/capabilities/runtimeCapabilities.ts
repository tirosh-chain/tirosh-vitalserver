import type { RuntimeControlCapabilities } from "@/domain/runtime-control/contracts/runtimeControlTypes";

export function canApplyRuntimeSettings(
  capabilities: RuntimeControlCapabilities | undefined
): boolean {
  return Boolean(
    capabilities?.canEditVMResources ||
      capabilities?.canEditNetworkExposure ||
      capabilities?.canOpenLocalFiles ||
      capabilities?.canControlRuntimeServices ||
      capabilities?.canResetAdminPassword
  );
}

export function canControlRecovery(
  capabilities: RuntimeControlCapabilities | undefined
): boolean {
  return Boolean(capabilities?.canControlRuntimeServices);
}
