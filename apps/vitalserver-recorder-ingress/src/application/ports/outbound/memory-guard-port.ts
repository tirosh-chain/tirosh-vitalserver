import type { RuntimeMemoryGuardRead } from "../../../domain/memory-guard-types";

export type MemoryGuardPort = {
  read(): Promise<RuntimeMemoryGuardRead>;
};
