import { useEffect, useState } from "react";
import { getPlugins } from "../lib/api";

export default function Plugins() {
  const [plugins, setPlugins] = useState<any[]>([]);
  useEffect(() => { getPlugins().then(setPlugins).catch(() => {}); }, []);
  return (
    <div className="min-h-screen p-8 max-w-5xl mx-auto">
      <h1 className="text-2xl mb-6">Plugins</h1>
      <div className="grid grid-cols-2 gap-3">
        {plugins.map((p) => (
          <div key={p.name} className="rounded-xl border border-white/5 bg-white/[0.02] p-4">
            <div className="flex items-center justify-between">
              <span className="text-sm">{p.name}</span>
              <span className="text-xs text-fg/40">{p.category}</span>
            </div>
            <div className="text-xs text-fg/50 mt-1">phase {p.phase.join(", ")}</div>
            <div className="flex gap-1 mt-2">
              {p.tags.map((t: string) => (
                <span key={t} className="text-[10px] px-1.5 py-0.5 rounded bg-white/5 text-fg/60">{t}</span>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
