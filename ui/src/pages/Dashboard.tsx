import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import { Link, useNavigate } from "react-router-dom";
import { getScans, createScan } from "../lib/api";

export default function Dashboard() {
  const [scans, setScans] = useState<any[]>([]);
  const [target, setTarget] = useState("");
  const [mode, setMode] = useState(3);
  const [ack, setAck] = useState(false);
  const [busy, setBusy] = useState(false);
  const nav = useNavigate();

  const load = async () => { try { setScans(await getScans()); } catch {} };
  useEffect(() => { load(); const t = setInterval(load, 5000); return () => clearInterval(t); }, []);

  const launch = async () => {
    if (!target || !ack) return;
    setBusy(true);
    try { const s = await createScan({ target, mode, scope_ack: true }); nav(`/scans/${s.id}`); }
    finally { setBusy(false); }
  };

  return (
    <div className="min-h-screen flex">
      <aside className="w-72 border-r border-white/5 p-5 flex flex-col gap-4">
        <div className="text-lg font-medium tracking-tight">AutoBug</div>
        <div className="flex flex-col gap-2">
          <input value={target} onChange={(e) => setTarget(e.target.value)} placeholder="target.com"
            className="bg-white/5 rounded-lg px-3 py-2 text-sm outline-none border border-white/5 focus:border-accent/60" />
          <div className="flex gap-1">
            {[1,2,3].map((m) => (
              <button key={m} onClick={() => setMode(m)}
                className={`flex-1 text-xs py-2 rounded-lg border transition ${mode === m ? "border-accent text-accent bg-accent/10" : "border-white/5 text-fg/60"}`}>
                mode {m}
              </button>
            ))}
          </div>
          <label className="flex items-center gap-2 text-xs text-fg/60">
            <input type="checkbox" checked={ack} onChange={(e) => setAck(e.target.checked)} />
            I own or am authorized to test this target
          </label>
          <button disabled={!target || !ack || busy} onClick={launch}
            className="bg-accent text-white text-sm rounded-lg py-2 disabled:opacity-40">
            {busy ? "launching…" : "launch scan"}
          </button>
        </div>
        <Link to="/osint" className="text-xs text-fg/60 hover:text-fg">→ OSINT</Link>
        <Link to="/plugins" className="text-xs text-fg/60 hover:text-fg">→ Plugins</Link>
      </aside>
      <main className="flex-1 p-8">
        <h1 className="text-2xl font-medium mb-6">Scans</h1>
        <div className="flex flex-col gap-3">
          {scans.map((s) => (
            <motion.div key={s.id} layout initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}>
              <Link to={`/scans/${s.id}`} className="block rounded-xl border border-white/5 bg-white/[0.02] p-4 hover:border-white/10">
                <div className="flex items-center justify-between">
                  <div className="text-sm">{s.target}</div>
                  <div className="text-xs text-fg/40">mode {s.mode} · {s.status}</div>
                </div>
              </Link>
            </motion.div>
          ))}
          {scans.length === 0 && <div className="text-fg/40 text-sm">no scans yet</div>}
        </div>
      </main>
    </div>
  );
}
