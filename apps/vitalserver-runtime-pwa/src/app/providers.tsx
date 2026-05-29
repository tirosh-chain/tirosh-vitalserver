import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { PropsWithChildren } from "react";
import { useState } from "react";

import { RuntimeControlGatewayProvider } from "@/application/runtime-control/RuntimeControlGatewayContext";
import type { RuntimeControlGateway } from "@/application/runtime-control/runtimeControlGateway";
import type { AppSettings } from "@/shared/config/appSettings";
import { AppSettingsProvider } from "@/shared/config/AppSettingsContext";

export function AppProviders({
  children,
  runtimeControlGateway,
  settings
}: PropsWithChildren<{
  runtimeControlGateway: RuntimeControlGateway;
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
      <RuntimeControlGatewayProvider gateway={runtimeControlGateway}>
        <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
      </RuntimeControlGatewayProvider>
    </AppSettingsProvider>
  );
}
