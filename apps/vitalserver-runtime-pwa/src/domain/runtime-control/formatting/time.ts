export function formatLocalDateTime(value: string | null | undefined): string {
  if (!value) {
    return "Unknown";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  const offsetMinutes = -date.getTimezoneOffset();
  const sign = offsetMinutes >= 0 ? "+" : "-";
  const absoluteOffset = Math.abs(offsetMinutes);
  const offsetHours = Math.floor(absoluteOffset / 60)
    .toString()
    .padStart(2, "0");
  const offsetRemainder = (absoluteOffset % 60).toString().padStart(2, "0");

  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(
    date.getDate()
  )} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(
    date.getSeconds()
  )} ${sign}${offsetHours}:${offsetRemainder}`;
}

export function formatLocalDateTimeWithAge(
  value: string | null | undefined
): string {
  const formatted = formatLocalDateTime(value);
  const age = formatAgeSince(value);
  return age === "Unknown" ? formatted : `${formatted} · ${age} ago`;
}

export function formatAgeSince(value: string | null | undefined): string {
  if (!value) {
    return "Unknown";
  }

  const timestamp = new Date(value).getTime();
  if (Number.isNaN(timestamp)) {
    return "Unknown";
  }

  const seconds = Math.max(0, Math.floor((Date.now() - timestamp) / 1000));
  if (seconds < 60) {
    return `${seconds}s`;
  }
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) {
    return `${minutes}m`;
  }
  const hours = Math.floor(minutes / 60);
  if (hours < 48) {
    return `${hours}h`;
  }
  const days = Math.floor(hours / 24);
  return `${days}d`;
}

export function formatUptimeSince(value: string | null | undefined): string {
  if (!value) {
    return "Unknown";
  }

  const startedAt = new Date(value).getTime();
  if (Number.isNaN(startedAt)) {
    return "Unknown";
  }

  const seconds = Math.max(0, Math.floor((Date.now() - startedAt) / 1000));
  const days = Math.floor(seconds / 86_400);
  const remainder = seconds % 86_400;
  const hours = Math.floor(remainder / 3600);
  const minutes = Math.floor((remainder % 3600) / 60);
  const secs = remainder % 60;
  const clock = `${pad(hours)}:${pad(minutes)}:${pad(secs)}`;
  return days > 0 ? `${days}d ${clock}` : clock;
}

function pad(value: number): string {
  return value.toString().padStart(2, "0");
}
