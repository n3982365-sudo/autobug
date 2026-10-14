import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { getScan, getFindings } from "../lib/api";
import { connectScanWS } from "../lib/ws";
import DagView from "../components/DagView";
import FindingCard from "../components/FindingCard";
import SeverityRing from "../components/SeverityRing";

export default function ScanDetail() {
  const { id } = useParams();
  const [scan, setScan] = useState<any>(null);
  const [findings, setFindings] = useState<any[]>([]);
  const [status, setStatus] = useState<Record<string, string>>({});

  useEffect(() => {
    if (!id) return;
    getScan(id).then(setScan).catch(() => {});
    getFindings(id).then(setFindings).catch(() => {});
    const close = connectScanWS(id, (e) => {
      setStatus((s) => ({ ...s, [e.node]: e.level === "done" ? "done" : e.level === "warn" ? "fail" : "active" }));
      if (e.node === "vuln_scan" || e.node === "finding_dedup") getFindings(id).then(setFindings).catch(() => {});
    });
    const t = setInterval(() => getFindings(id).then(setFindings).catch(() => {}), 4000);
    return () => { close(); clearInterval(t); };
  }, [id]);

  const counts = findings.reduce((a: any, f) => { a[f.severity] = (a[f.severity] || 0) + 1; return a; }, {});

  return (
    <div className="min-h-screen flex">
      <div className="w-80 border-r border-white/5 p-5">
        <div className="text-sm text-fg/60 mb-4">{scan?.target}</div>
        <DagView status={status} />
      </div>
      <main className="flex-1 p-8">
        <div className="flex items-center gap-8 mb-8">
          <SeverityRing counts={counts} />
          <div className="grid grid-cols-5 gap-4">
            {["critical","high","medium","low","info"].map((s) => (
              <div key={s} className="text-center">
                <div className="text-2xl">{counts[s] || 0}</div>
                <div className="text-xs text-fg/40 uppercase">{s}</div>
              </div>
            ))}
          </div>
        </div>
        <div className="flex flex-col gap-3">
          {findings.map((f) => <FindingCard key={f.id} f={f} />)}
        </div>
      </main>
    </div>
  );
}
