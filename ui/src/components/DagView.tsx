import { motion } from "framer-motion";
const NODES = ["scope_validate","target_intake","passive_recon","asset_dedup","asset_graph","active_recon","live_hosts","tech_fingerprint","osint_recon","vuln_scan","finding_dedup","severity_triage","exploit_verify","screenshot","report_generate","notify"];
export default function DagView({ status }: { status: Record<string, string> }) {
  return (
    <div className="flex flex-col gap-3 p-6">
      {NODES.map((n, i) => {
        const s = status[n] || "pending";
        const color = s === "done" ? "#22c55e" : s === "active" ? "#3B82F6" : s === "fail" ? "#B91C1C" : "#3f3f46";
        return (
          <motion.div key={n} initial={{ opacity: 0, x: -12 }} animate={{ opacity: 1, x: 0 }}
            transition={{ delay: i * 0.02, type: "spring", stiffness: 300, damping: 24 }}
            className="flex items-center gap-3">
            <motion.span animate={{ scale: s === "active" ? [1, 1.25, 1] : 1 }}
              transition={{ repeat: s === "active" ? Infinity : 0, duration: 1.2 }}
              className="w-3 h-3 rounded-full" style={{ background: color }} />
            <span className="text-sm text-fg/80">{n}</span>
            <span className="ml-auto text-xs text-fg/40">{s}</span>
          </motion.div>
        );
      })}
    </div>
  );
}
