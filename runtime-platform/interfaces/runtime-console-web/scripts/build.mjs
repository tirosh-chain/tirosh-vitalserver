import { cp, mkdir, rm } from "node:fs/promises";
import { build } from "esbuild";

await rm("dist", { recursive: true, force: true });
await mkdir("dist", { recursive: true });
await build({
  entryPoints: ["src/runtime_console_entry.tsx"],
  bundle: true,
  format: "iife",
  platform: "browser",
  target: ["chrome120"],
  outfile: "dist/runtime-console.js",
  jsx: "automatic",
  sourcemap: true,
  logLevel: "info",
});
await cp("src/runtime_console.html", "dist/index.html");
