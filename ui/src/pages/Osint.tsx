import { useState } from "react";
import { motion } from "framer-motion";
import { runOsint } from "../lib/api";
const TYPES = ["email", "domain", "phone", "image"] as const;

export default function Osint() {
  const [type, setType] = useState<typeof TYPES[number]>("email");
  const [value, setValue] = useState("");
  const [result, setResult] = useState<any>(null);
  const [busy, setBusy] = useState(false);

  const run = async () => {
    setBusy(true); setResult(null);
    try { setResult(await runOsint({ type, value })); } finally { setBusy(false); }
  };

  return (
    <div className="min-h-screen p-8 max-w-3xl mx-auto">
      <h1 className="text-2xl mb-6">OSINT</h1>
      <div className="flex gap-2 mb-4">
        {TYPES.map((t) => (
          <button key={t} onClick={() => setType(t)}
            className={`px-3 py-1.5 text-xs rounded-lg border ${type === t ? "border-accent text-accent bg-accent/10" : "border-white/5 text-fg/60"}`}>
            {t}
          </button>
        ))}
      </div>
      <div className="flex gap-2">
        <input value={value} onChange={(e) => setValue(e.target.value)}
          placeholder={type === "email" ? "user@example.com" : type === "domain" ? "example.com" : type === "phone" ? "+91..." : "image URL"}
          className="flex-1 bg-white/5 rounded-lg px-3 py-2 text-sm outline-none border border-white/5 focus:border-accent/60" />
        <button onClick={run} disabled={!value || busy} className="bg-accent text-white text-sm rounded-lg px-4 disabled:opacity-40">
          {busy ? "…" : "run"}
        </button>
      </div>
      {result && (
        <motion.pre initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}
          className="mt-6 text-xs bg-white/[0.02] border border-white/5 rounded-xl p-4 overflow-auto">
          {JSON.stringify(result, null, 2)}
        </motion.pre>
      )}
    </div>
  );
}
