import type { RecorderObservabilityRepositoryPort } from "./ports/outbound/recorder-observability-repository-port";
import { shouldReplaceCurrent } from "../domain/recorder-observability";

export function createRecorderObservabilityProjector({
  repository,
  intervalMs,
  batchSize,
}: {
  repository: RecorderObservabilityRepositoryPort;
  intervalMs: number;
  batchSize: number;
}) {
  let timer: NodeJS.Timeout | null = null;
  let running: Promise<number> | null = null;

  const runOnce = async (): Promise<number> => {
    if (running) return running;
    running = (async () => {
      const candidates = await repository.listPendingProjection(batchSize);
      for (const candidate of candidates) {
        try {
          const current = await repository.readCurrent(
            candidate.vrcode,
            candidate.resourceType,
          );
          await repository.applyProjection(
            candidate,
            shouldReplaceCurrent(candidate, current),
          );
        } catch (error) {
          await repository.failProjection(candidate.recordId, errorMessage(error));
        }
      }
      return candidates.length;
    })();
    try {
      return await running;
    } finally {
      running = null;
    }
  };

  return {
    async runOnce() {
      return runOnce();
    },
    start() {
      if (timer) return;
      timer = setInterval(() => {
        runOnce().catch((error) => {
          console.error(
            `[recorder-observability-projector] ${errorMessage(error)}`,
          );
        });
      }, intervalMs);
      timer.unref();
      void runOnce();
    },
    async stop() {
      if (timer) clearInterval(timer);
      timer = null;
      if (running) await running;
    },
  };
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

module.exports = { createRecorderObservabilityProjector };
