import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import { VitePWA } from "vite-plugin-pwa";

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      includeAssets: [],
      manifest: false,
      workbox: {
        navigateFallback: "/index.html",
        runtimeCaching: [
          {
            urlPattern: ({ url }) => url.pathname.startsWith("/runtime/"),
            handler: "NetworkOnly",
            options: {
              cacheName: "runtime-control-api"
            }
          },
          {
            urlPattern: ({ url }) => url.pathname.startsWith("/vitaldb/"),
            handler: "NetworkOnly",
            options: {
              cacheName: "vitaldb-runtime-api"
            }
          },
          {
            urlPattern: ({ url }) => url.pathname.startsWith("/host/"),
            handler: "NetworkOnly",
            options: {
              cacheName: "host-runtime-api"
            }
          }
        ]
      }
    })
  ],
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
