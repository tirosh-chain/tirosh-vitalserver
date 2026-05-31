import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { PropsWithChildren } from "react";
import { useState } from "react";

import { ConsoleGatewayProvider } from "@/console/gatewayContext";
import type { ConsoleGateway } from "@/console/gateway";
import type { AppSettings } from "@/config/appSettings";
import { AppSettingsProvider } from "@/config/AppSettingsContext";

export function AppProviders({
  children,
  consoleGateway,
  settings
}: PropsWithChildren<{
  consoleGateway: ConsoleGateway;
  settings: AppSettings;
}>) {
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
      <ConsoleGatewayProvider gateway={consoleGateway}>
        <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
      </ConsoleGatewayProvider>
    </AppSettingsProvider>
  );
}
