import { motion } from "framer-motion";
const SEV: Record<string, string> = {
  critical: "text-sev-crit border-sev-crit",
  high: "text-sev-high border-sev-high",
  medium: "text-sev-med border-sev-med",
  low: "text-sev-low border-sev-low",
  info: "text-sev-info border-sev-info",
};
export default function FindingCard({ f }: { f: any }) {
  const c = SEV[f.severity] || SEV.info;
  return (
    <motion.div initial={{ opacity: 0, x: 20, filter: "blur(4px)" }} animate={{ opacity: 1, x: 0, filter: "blur(0px)" }}
      transition={{ duration: 0.25, ease: "easeOut" }}
      className={`rounded-xl border bg-white/[0.02] p-4 ${c.split(" ")[1]}`}>
      <div className="flex items-center justify-between">
        <span className={`text-xs uppercase tracking-wider ${c.split(" ")[0]}`}>{f.severity}</span>
        <span className="text-xs text-fg/40">{f.tool}</span>
      </div>
      <div className="mt-2 text-sm text-fg/90">{f.title}</div>
      <div className="mt-1 text-xs text-fg/50 truncate">{f.url}</div>
    </motion.div>
  );
}
