import { motion } from "framer-motion";
export default function SeverityRing({ counts }: { counts: Record<string, number> }) {
  const total = Object.values(counts).reduce((a, b) => a + b, 0) || 1;
  const order = ["critical","high","medium","low","info"];
  const colors = ["#B91C1C","#C2410C","#A16207","#4D7C0F","#3B82F6"];
  let offset = 0;
  const r = 42, c = 2 * Math.PI * r;
  return (
    <svg viewBox="0 0 100 100" className="w-32 h-32 -rotate-90">
      {order.map((s, i) => {
        const v = counts[s] || 0;
        const len = (v / total) * c;
        const el = (
          <motion.circle key={s} cx="50" cy="50" r={r} fill="none" stroke={colors[i]} strokeWidth="8"
            strokeDasharray={`${len} ${c}`} strokeDashoffset={-offset}
            initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: 0.5, delay: i * 0.05 }} />
        );
        offset += len;
        return el;
      })}
    </svg>
  );
}
