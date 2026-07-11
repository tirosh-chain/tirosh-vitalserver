import type { ControlCapabilities } from "@/domain/runtime-control/contracts/runtimeControlTypes";

export function canApplyRuntimeSettings(
  capabilities: ControlCapabilities | undefined
): boolean {
  return Boolean(
    capabilities?.canEditRuntimeProviderResources ||
      capabilities?.canEditNetworkExposure ||
      capabilities?.canOpenLocalFiles ||
      capabilities?.canControlRuntimeServices ||
      capabilities?.canResetAdminPassword
  );
}

export function canApplyRuntimeProductSettings(
  capabilities: ControlCapabilities | undefined
): boolean {
  return capabilities?.canApplyRuntimeProductSettings === true;
}

export function canApplyRuntimeAdminPassword(
  capabilities: ControlCapabilities | undefined
): boolean {
  return capabilities?.canApplyRuntimeAdminPassword === true;
}

export function canApplyRuntimeRedisRelaySettings(
  capabilities: ControlCapabilities | undefined
): boolean {
  return capabilities?.canApplyRuntimeRedisRelaySettings === true;
}

export function canControlRecovery(
  capabilities: ControlCapabilities | undefined
): boolean {
  return Boolean(capabilities?.canControlRuntimeServices);
}
