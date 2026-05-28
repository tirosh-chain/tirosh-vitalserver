const recorderStatusLabels: Record<string, string> = {
  online: "Online",
  stale: "Stale",
  offline: "Offline",
  unknown: "Unknown"
};

export function formatRecorderStatus(value: string | null | undefined): string {
  if (!value) {
    return "Unknown";
  }
  return recorderStatusLabels[value] ?? value;
}

export function recorderStatusTone(
  value: string | null | undefined
): "success" | "warning" | "danger" | "neutral" {
  switch (value) {
    case "online":
      return "success";
    case "stale":
      return "warning";
    case "offline":
      return "danger";
    default:
      return "neutral";
  }
}

export function formatBoolean(value: boolean | null | undefined): string {
  if (value === true) {
    return "Yes";
  }
  if (value === false) {
    return "No";
  }
  return "Unknown";
}
