import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { PropsWithChildren } from "react";
import { useState } from "react";

import type { AppSettings } from "@/shared/config/appSettings";
import { AppSettingsProvider } from "@/shared/config/AppSettingsContext";

export function AppProviders({
  children,
  settings
}: PropsWithChildren<{ settings: AppSettings }>) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            refetchOnWindowFocus: settings.queries.refetchOnWindowFocus,
            retry: settings.queries.retry,
            staleTime: settings.queries.staleTimeMs
          }
        }
      })
  );

  return (
    <AppSettingsProvider settings={settings}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </AppSettingsProvider>
  );
}
