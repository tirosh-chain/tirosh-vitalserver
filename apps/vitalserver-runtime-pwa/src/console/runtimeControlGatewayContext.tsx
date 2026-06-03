import {
  createContext,
  useContext,
  type PropsWithChildren
} from "react";

import type { RuntimeControlGateway } from "./runtimeControlGateway";

const RuntimeControlGatewayContext =
  createContext<RuntimeControlGateway | null>(null);

export function RuntimeControlGatewayProvider({
  children,
  gateway
}: PropsWithChildren<{ gateway: RuntimeControlGateway }>) {
  return (
    <RuntimeControlGatewayContext.Provider value={gateway}>
      {children}
    </RuntimeControlGatewayContext.Provider>
  );
}

export function useRuntimeControlGateway(): RuntimeControlGateway {
  const gateway = useContext(RuntimeControlGatewayContext);
  if (!gateway) {
    throw new Error("RuntimeControlGatewayProvider is missing");
  }
  return gateway;
}
