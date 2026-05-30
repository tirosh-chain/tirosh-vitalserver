export const logExportPathMessages = {
  invalid: "Choose an absolute .zip path on the Mac running Runtime Control API.",
  protected:
    "Choose a writable local folder. iCloud Drive, Desktop, Documents, system, and app-managed folders are not supported for log export."
} as const;

export function validateHostLogExportPath(path: string): string | null {
  const normalized = normalizePath(path);
  if (!normalized || !normalized.startsWith("/") || !normalized.endsWith(".zip")) {
    return logExportPathMessages.invalid;
  }

  if (isProtectedPath(normalized)) {
    return logExportPathMessages.protected;
  }

  return null;
}

function normalizePath(path: string): string {
  return path.trim().replace(/\/+/g, "/");
}

function isProtectedPath(path: string): boolean {
  return (
    isICloudDrivePath(path) ||
    isProtectedUserPath(path) ||
    isSystemManagedPath(path)
  );
}

function isICloudDrivePath(path: string): boolean {
  return (
    path.includes("/Library/Mobile Documents/") ||
    path.endsWith("/Library/Mobile Documents")
  );
}

function isProtectedUserPath(path: string): boolean {
  return /^\/Users\/[^/]+\/(?:Desktop|Documents)(?:\/|$)/.test(path);
}

function isSystemManagedPath(path: string): boolean {
  return (
    path === "/" ||
    path === "/Applications" ||
    path.startsWith("/Applications/") ||
    path === "/Library" ||
    path.startsWith("/Library/") ||
    path === "/System" ||
    path.startsWith("/System/") ||
    path === "/bin" ||
    path.startsWith("/bin/") ||
    path === "/sbin" ||
    path.startsWith("/sbin/") ||
    path === "/usr" ||
    (path.startsWith("/usr/") && !path.startsWith("/usr/local/"))
  );
}
