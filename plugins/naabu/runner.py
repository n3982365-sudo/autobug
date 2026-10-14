import tempfile, subprocess, json
from plugins.runner_base import PluginBase
from plugins._schema import Result

class Plugin(PluginBase):
    def run(self, target: str, **kw):
        wd = tempfile.mkdtemp(prefix="autobug_naabu_")
        cmd = f"docker run --rm -v {wd}:/out projectdiscovery/naabu:latest -host {target} -silent -json -o /out/ports.json -top-ports 1000"
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=900)
        return wd, out.stdout, out.stderr
    def parse(self, workdir: str) -> list[Result]:
        out: list[Result] = []
        try:
            for line in open(f"{workdir}/ports.json"):
                d = json.loads(line)
                out.append(Result(kind="open_port", target=d.get("host",""), port=d.get("port"), severity="info", raw=d))
        except Exception:
            pass
        return out
