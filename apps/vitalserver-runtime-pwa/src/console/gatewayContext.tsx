import {
  createContext,
  useContext,
  type PropsWithChildren
} from "react";

import type { ConsoleGateway } from "./gateway";

const ConsoleGatewayContext =
  createContext<ConsoleGateway | null>(null);

export function ConsoleGatewayProvider({
  children,
  gateway
}: PropsWithChildren<{ gateway: ConsoleGateway }>) {
  return (
    <ConsoleGatewayContext.Provider value={gateway}>
      {children}
    </ConsoleGatewayContext.Provider>
  );
}

export function useConsoleGateway(): ConsoleGateway {
  const gateway = useContext(ConsoleGatewayContext);
  if (!gateway) {
    throw new Error("ConsoleGatewayProvider is missing");
  }
  return gateway;
}
