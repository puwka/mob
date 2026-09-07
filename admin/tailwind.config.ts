import type { Config } from "tailwindcss";

export default {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        graphite: {
          950: "#0b0c0e",
          900: "#111317",
          850: "#16191e",
          800: "#1c2026",
          700: "#262b33",
          600: "#343b46",
        },
        lime: {
          DEFAULT: "#A4C639",
          dim: "#8eab30",
          soft: "rgba(164, 198, 57, 0.12)",
        },
      },
      fontFamily: {
        sans: ["var(--font-admin)", "Segoe UI", "sans-serif"],
        mono: ["var(--font-mono)", "ui-monospace", "monospace"],
      },
      boxShadow: {
        panel: "0 1px 0 rgba(255,255,255,0.03), 0 8px 24px rgba(0,0,0,0.35)",
      },
    },
  },
  plugins: [],
} satisfies Config;
