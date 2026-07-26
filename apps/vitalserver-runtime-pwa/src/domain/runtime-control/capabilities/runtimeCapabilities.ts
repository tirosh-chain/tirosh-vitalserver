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

/** Platform-owned capability for the portable Runtime Provider lifecycle action. */
export function canRestartRuntimeProvider(
  capabilities: ControlCapabilities | undefined
): boolean {
  return capabilities?.canControlRuntimeServices === true;
}

/** Guest-owned capability for the optional datastore-maintenance operation. */
export function canRepairRuntimeDatastore(
  capabilities: ControlCapabilities | undefined
): boolean {
  return capabilities?.canRepairRuntimeDatastore === true;
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
