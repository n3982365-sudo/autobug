export function connectScanWS(scanId: number | string, onEvent: (e: any) => void): () => void {
  const API = (import.meta as any).env?.VITE_API || "http://localhost:8000";
  const wsUrl = API.replace(/^http/, "ws") + `/ws/scans/${scanId}`;
  let ws: WebSocket | null = null;
  let closed = false;
  let backoff = 500;
  const open = () => {
    if (closed) return;
    ws = new WebSocket(wsUrl);
    ws.onmessage = (m) => { try { onEvent(JSON.parse(m.data)); } catch {} };
    ws.onopen = () => { backoff = 500; };
    ws.onclose = () => { if (closed) return; setTimeout(open, backoff); backoff = Math.min(backoff * 2, 8000); };
  };
  open();
  return () => { closed = true; ws?.close(); };
}
