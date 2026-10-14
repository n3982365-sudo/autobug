import tempfile, subprocess, json
from plugins.runner_base import PluginBase
from plugins._schema import Result

class Plugin(PluginBase):
    def run(self, target: str, ports: str = "1-1000", **kw):
        wd = tempfile.mkdtemp(prefix="autobug_nmap_")
        cmd = f"docker run --rm -v {wd}:/out instrumentisto/nmap:latest -sV -sC -p {ports} -oX /out/scan.xml -oJ /out/ports.json {target}"
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=1800)
        return wd, out.stdout, out.stderr
    def parse(self, workdir: str) -> list[Result]:
        try:
            data = json.load(open(f"{workdir}/ports.json"))
        except Exception:
            return []
        out: list[Result] = []
        for host in data.get("hosts", []):
            addr = host.get("addr", "")
            for port in host.get("ports", []):
                out.append(Result(kind="open_port", target=addr, port=port.get("port"),
                                  service=(port.get("service") or {}).get("name"),
                                  severity="info", raw=port))
        return out
