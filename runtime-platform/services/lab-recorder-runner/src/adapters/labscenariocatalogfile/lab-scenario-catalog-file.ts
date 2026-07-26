import { readFile } from "node:fs/promises";

import type { LabScenarioDefinition } from "../../labrecorderrunnerdomain/lab-recorder-run-contracts.js";

interface EncodedLabScenarioCatalog {
  schemaVersion?: unknown;
  catalogId?: unknown;
  scenarios?: unknown;
}

interface EncodedLabScenario {
  id?: unknown;
  packetIntervalMilliseconds?: unknown;
  minimumPacketCountBeforeStop?: unknown;
  archiveOnTerminalStop?: unknown;
}

// LabScenarioCatalog is desired product configuration. The Runner consumes it
// to resolve a scenario ID; it never discovers scenarios from a file name,
// virtual-recorder label, or stale process state.
export class LabScenarioCatalog {
  private readonly scenariosByID: ReadonlyMap<string, LabScenarioDefinition>;

  private constructor(readonly catalogID: string, scenarios: readonly LabScenarioDefinition[]) {
    this.scenariosByID = new Map(scenarios.map((scenario) => [scenario.id, Object.freeze({ ...scenario })]));
  }

  public static async read(path: string): Promise<LabScenarioCatalog> {
    let encoded: string;
    try {
      encoded = await readFile(path, "utf8");
    } catch (error) {
      throw new Error(`Lab scenario catalog cannot be read: ${errorMessage(error)}`);
    }
    let decoded: unknown;
    try {
      decoded = JSON.parse(encoded) as unknown;
    } catch {
      throw new Error("Lab scenario catalog JSON cannot be decoded");
    }
    return LabScenarioCatalog.decode(decoded);
  }

  public static decode(value: unknown): LabScenarioCatalog {
    if (!isRecord(value) || value.schemaVersion !== "v1" || !isIdentifier(value.catalogId) || !Array.isArray(value.scenarios) || value.scenarios.length === 0) {
      throw new Error("Lab scenario catalog must contain schemaVersion v1, catalogId, and one or more scenarios");
    }
    const decoded = value as EncodedLabScenarioCatalog;
    const rawScenarios = value.scenarios as unknown[];
    const scenarios = rawScenarios.map((candidate: unknown) => decodeScenario(candidate));
    const unique = new Set(scenarios.map((scenario) => scenario.id));
    if (unique.size !== scenarios.length) {
      throw new Error("Lab scenario catalog cannot contain duplicate scenario IDs");
    }
    return new LabScenarioCatalog(decoded.catalogId as string, scenarios);
  }

  public find(id: string): LabScenarioDefinition | undefined {
    const scenario = this.scenariosByID.get(id);
    return scenario === undefined ? undefined : { ...scenario };
  }
}

function decodeScenario(value: unknown): LabScenarioDefinition {
  if (!isRecord(value)) {
    throw new Error("Lab scenario must be an object");
  }
  const scenario = value as EncodedLabScenario;
  if (!isIdentifier(scenario.id) || !Number.isInteger(scenario.packetIntervalMilliseconds) || (scenario.packetIntervalMilliseconds as number) < 20 || (scenario.packetIntervalMilliseconds as number) > 60_000 || !Number.isInteger(scenario.minimumPacketCountBeforeStop) || (scenario.minimumPacketCountBeforeStop as number) < 1 || (scenario.minimumPacketCountBeforeStop as number) > 10_000 || typeof scenario.archiveOnTerminalStop !== "boolean") {
    throw new Error("Lab scenario has invalid packet interval, minimum packet count, or archive policy");
  }
  return {
    id: scenario.id as string,
    packetIntervalMilliseconds: scenario.packetIntervalMilliseconds as number,
    minimumPacketCountBeforeStop: scenario.minimumPacketCountBeforeStop as number,
    archiveOnTerminalStop: scenario.archiveOnTerminalStop,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isIdentifier(value: unknown): value is string {
  return typeof value === "string" && /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/.test(value);
}

function errorMessage(value: unknown): string {
  return value instanceof Error ? value.message : "unknown error";
}
