import { cp, mkdir, rm, stat } from "node:fs/promises";
import { build } from "esbuild";

async function requireRendererBuild() {
  try {
    await stat("../runtime-console-web/dist/index.html");
  } catch {
    throw new Error("Runtime Console renderer is missing. Build @tirosh-chain/runtime-console-web before the desktop shell.");
  }
}

await requireRendererBuild();
await rm("dist", { recursive: true, force: true });
await mkdir("dist", { recursive: true });
await build({
  entryPoints: ["src/runtime_console_desktop_main.ts"],
  bundle: true,
  external: ["electron"],
  format: "cjs",
  platform: "node",
  target: ["node20"],
  outfile: "dist/runtime-console-main.cjs",
  sourcemap: true,
  logLevel: "info",
});
await build({
  entryPoints: ["src/runtime_console_desktop_preload.ts"],
  bundle: true,
  external: ["electron"],
  format: "cjs",
  platform: "node",
  target: ["node20"],
  outfile: "dist/runtime-console-preload.cjs",
  sourcemap: true,
  logLevel: "info",
});
await build({
  entryPoints: ["src/host_agent_local_control_transport.ts"],
  bundle: true,
  format: "esm",
  platform: "node",
  target: ["node20"],
  outfile: "dist/host-agent-local-control-transport.mjs",
  sourcemap: true,
  logLevel: "info",
});
await cp("../runtime-console-web/dist", "dist/renderer", { recursive: true });
