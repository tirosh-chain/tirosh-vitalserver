const runtimeStateLabels: Record<string, string> = {
  installing: "Installing",
  initializing: "Initializing",
  updating: "Updating",
  recovering: "Recovering",
  healthy: "Healthy",
  degraded: "Degraded",
  critical: "Critical"
};

export function formatRuntimeState(value: string | null | undefined): string {
  if (!value) {
    return "Unknown";
  }
  return runtimeStateLabels[value] ?? value;
}

export function runtimeStateTone(
  value: string | null | undefined
): "success" | "warning" | "danger" | "neutral" {
  switch (value) {
    case "healthy":
      return "success";
    case "installing":
    case "initializing":
    case "updating":
    case "recovering":
    case "degraded":
      return "warning";
    case "critical":
      return "danger";
    default:
      return "neutral";
  }
}
