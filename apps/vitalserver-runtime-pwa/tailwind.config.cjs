/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    screens: {
      xs: "390px",
      sm: "640px",
      md: "768px",
      lg: "1024px",
      xl: "1440px",
      "2xl": "1920px"
    },
    extend: {
      colors: {
        app: {
          bg: "#eef2f4",
          panel: "#ffffff",
          text: "#2b2d2f",
          muted: "#7d7f82",
          border: "#e1e4e7",
          control: "#d8dde1",
          accent: "#1683f7",
          accentSoft: "#e9f4ff",
          success: "#31c75f",
          warning: "#ff8f28",
          danger: "#ff3b49",
          neutral: "#9aa0a6"
        }
      },
      borderRadius: {
        panel: "8px",
        control: "7px"
      },
      fontFamily: {
        sans: [
          "-apple-system",
          "BlinkMacSystemFont",
          "\"Segoe UI\"",
          "sans-serif"
        ],
        mono: ["\"SFMono-Regular\"", "Consolas", "\"Liberation Mono\"", "monospace"]
      },
      boxShadow: {
        control: "0 1px 3px rgba(0, 0, 0, 0.12)"
      }
    }
  },
  plugins: []
};
