export type AppSettingsEnv = Record<string, string | boolean | undefined>;

export type RuntimeControlSettings = {
  apiBaseURL: string;
  devProxyTarget: string;
  token: string;
  defaultPort: number;
  defaultProxyPort: number;
};

export type QuerySettings = {
  refetchOnWindowFocus: boolean;
  retry: number;
  staleTimeMs: number;
};

export type PWASettings = {
  devServerPort: number;
  previewPort: number;
};

export type AppSettings = {
  runtimeControl: RuntimeControlSettings;
  queries: QuerySettings;
  pwa: PWASettings;
};

export const DEFAULT_APP_SETTINGS: AppSettings = {
	runtimeControl: {
		apiBaseURL: "",
		devProxyTarget: "http://127.0.0.1:18321",
		token: "",
    defaultPort: 18_321,
    defaultProxyPort: 80
  },
  queries: {
    refetchOnWindowFocus: false,
    retry: 1,
    staleTimeMs: 1_000
  },
  pwa: {
    devServerPort: 5_174,
    previewPort: 4_174
  }
};

export function loadAppSettings(env: AppSettingsEnv = {}): AppSettings {
  const defaultPort = readPort(
    env,
    ["VITE_RUNTIME_CONTROL_DEFAULT_PORT", "RUNTIME_CONTROL_DEFAULT_PORT"],
    DEFAULT_APP_SETTINGS.runtimeControl.defaultPort
  );
  const apiBaseURL = trimTrailingSlash(
    readString(
      env,
      ["VITE_RUNTIME_CONTROL_API_BASE_URL", "RUNTIME_CONTROL_API_BASE_URL"],
      DEFAULT_APP_SETTINGS.runtimeControl.apiBaseURL
    )
  );
  const devProxyTarget = trimTrailingSlash(
    readString(
      env,
      [
        "VITE_RUNTIME_CONTROL_DEV_PROXY_TARGET",
        "RUNTIME_CONTROL_DEV_PROXY_TARGET",
        "VITE_RUNTIME_CONTROL_API_BASE_URL",
        "RUNTIME_CONTROL_API_BASE_URL"
      ],
      apiBaseURL || `http://127.0.0.1:${defaultPort}`
    )
  );

  return {
    runtimeControl: {
      apiBaseURL,
      devProxyTarget,
      defaultPort,
      defaultProxyPort: readPort(
        env,
        ["VITE_RUNTIME_CONTROL_DEFAULT_PROXY_PORT", "RUNTIME_CONTROL_DEFAULT_PROXY_PORT"],
        DEFAULT_APP_SETTINGS.runtimeControl.defaultProxyPort
      ),
      token: readString(
        env,
        ["VITE_RUNTIME_CONTROL_TOKEN", "RUNTIME_CONTROL_TOKEN"],
        DEFAULT_APP_SETTINGS.runtimeControl.token
      )
    },
    queries: {
      refetchOnWindowFocus: readBoolean(
        env,
        ["VITE_QUERY_REFETCH_ON_WINDOW_FOCUS", "QUERY_REFETCH_ON_WINDOW_FOCUS"],
        DEFAULT_APP_SETTINGS.queries.refetchOnWindowFocus
      ),
      retry: readNumber(
        env,
        ["VITE_QUERY_RETRY", "QUERY_RETRY"],
        DEFAULT_APP_SETTINGS.queries.retry
      ),
      staleTimeMs: readNumber(
        env,
        ["VITE_QUERY_STALE_TIME_MS", "QUERY_STALE_TIME_MS"],
        DEFAULT_APP_SETTINGS.queries.staleTimeMs
      )
    },
    pwa: {
      devServerPort: readPort(
        env,
        ["VITE_PWA_DEV_SERVER_PORT", "PWA_DEV_SERVER_PORT"],
        DEFAULT_APP_SETTINGS.pwa.devServerPort
      ),
      previewPort: readPort(
        env,
        ["VITE_PWA_PREVIEW_PORT", "PWA_PREVIEW_PORT"],
        DEFAULT_APP_SETTINGS.pwa.previewPort
      )
    }
  };
}

export function loadBrowserAppSettings(): AppSettings {
  return loadAppSettings((import.meta as { env?: AppSettingsEnv }).env ?? {});
}

function readString(
  env: AppSettingsEnv,
  keys: string[],
  fallback: string
): string {
  for (const key of keys) {
    const value = env[key];
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }
  return fallback;
}

function readNumber(
  env: AppSettingsEnv,
  keys: string[],
  fallback: number
): number {
  const value = readString(env, keys, "");
  if (!value) {
    return fallback;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function readPort(
  env: AppSettingsEnv,
  keys: string[],
  fallback: number
): number {
  const value = readNumber(env, keys, fallback);
  return Number.isInteger(value) && value > 0 && value <= 65_535 ? value : fallback;
}

function readBoolean(
  env: AppSettingsEnv,
  keys: string[],
  fallback: boolean
): boolean {
  const value = readString(env, keys, "");
  if (!value) {
    return fallback;
  }
  return ["1", "true", "yes", "on"].includes(value.toLowerCase());
}

function trimTrailingSlash(value: string): string {
  return value.endsWith("/") ? value.slice(0, -1) : value;
}
