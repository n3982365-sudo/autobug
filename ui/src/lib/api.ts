const API = (import.meta as any).env?.VITE_API || "http://localhost:8000";
export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const r = await fetch(`${API}${path}`, { ...init, headers: { "Content-Type": "application/json", ...(init?.headers || {}) } });
  if (!r.ok) throw new Error(await r.text());
  return r.json();
}
export const getScans = () => api<any[]>("/api/scans");
export const getScan = (id: string | number) => api<any>(`/api/scans/${id}`);
export const createScan = (body: any) => api<any>("/api/scans", { method: "POST", body: JSON.stringify(body) });
export const getFindings = (id: string | number) => api<any[]>(`/api/findings?scan_id=${id}`);
export const getPlugins = () => api<any[]>("/api/plugins");
export const runOsint = (body: any) => api<any>("/api/osint/run", { method: "POST", body: JSON.stringify(body) });
