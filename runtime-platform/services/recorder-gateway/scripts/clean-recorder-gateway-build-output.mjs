// The TypeScript compiler does not remove JavaScript emitted for a source file
// that later disappears or is renamed. Recorder Gateway packaging must never
// retain a former composition root or adapter, so this explicit build effect
// clears only this package's declared generated output before every compile.
import { rm } from "node:fs/promises";

const outputDirectory = new URL("../dist/", import.meta.url);
await rm(outputDirectory, { recursive: true, force: true });
