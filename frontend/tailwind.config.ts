import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        aegis: {
          dark: "#0a0e1a",
          card: "#111827",
          border: "#1f2937",
          accent: "#3b82f6",
          green: "#22c55e",
          red: "#ef4444",
          yellow: "#eab308",
        },
      },
    },
  },
  plugins: [],
};

export default config;
