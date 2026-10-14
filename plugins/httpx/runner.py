import tempfile, subprocess, json
from plugins.runner_base import PluginBase
from plugins._schema import Result

class Plugin(PluginBase):
    def run(self, target: str, **kw):
        wd = tempfile.mkdtemp(prefix="autobug_httpx_")
        cmd = f"docker run --rm -v {wd}:/out projectdiscovery/httpx:latest -u {target} -silent -json -o /out/live.json -status-code -title -tech-detect"
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=600)
        return wd, out.stdout, out.stderr
    def parse(self, workdir: str) -> list[Result]:
        out: list[Result] = []
        try:
            for line in open(f"{workdir}/live.json"):
                d = json.loads(line)
                out.append(Result(kind="live_host", target=d.get("url", d.get("input","")), severity="info", raw=d))
        except Exception:
            pass
        return out
