import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5174,
    proxy: {
      "/runtime": "http://127.0.0.1:18321",
      "/vitaldb": "http://127.0.0.1:18321",
      "/host": "http://127.0.0.1:18321",
      "/dev/testkit": "http://127.0.0.1:18321"
    }
  },
  preview: {
    port: 4174
  }
});
