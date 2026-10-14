export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "#0A0A0B",
        fg: "#EDEDEF",
        accent: "#3B82F6",
        sev: { crit: "#B91C1C", high: "#C2410C", med: "#A16207", low: "#4D7C0F", info: "#3B82F6" },
      },
    },
  },
  plugins: [],
};
