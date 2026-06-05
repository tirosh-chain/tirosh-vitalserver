import type { PropsWithChildren } from "react";
import { createContext, useContext } from "react";

import type { AppSettings } from "./appSettings";

const AppSettingsContext = createContext<AppSettings | null>(null);

export function AppSettingsProvider({
  children,
  settings
}: PropsWithChildren<{ settings: AppSettings }>) {
  return (
    <AppSettingsContext.Provider value={settings}>
      {children}
    </AppSettingsContext.Provider>
  );
}

export function useAppSettings(): AppSettings {
  const settings = useContext(AppSettingsContext);
  if (!settings) {
    throw new Error("App settings were not provided");
  }
  return settings;
}
