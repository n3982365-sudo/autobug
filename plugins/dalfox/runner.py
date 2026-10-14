import tempfile, subprocess, json
from plugins.runner_base import PluginBase
from plugins._schema import Result

class Plugin(PluginBase):
    def run(self, target: str, **kw):
        wd = tempfile.mkdtemp(prefix="autobug_dalfox_")
        cmd = f"docker run --rm -v {wd}:/out hahwul/dalfox:latest url {target} --silence --output /out/findings.json --format json"
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=900)
        return wd, out.stdout, out.stderr
    def parse(self, workdir: str) -> list[Result]:
        out: list[Result] = []
        try:
            data = json.load(open(f"{workdir}/findings.json"))
            items = data if isinstance(data, list) else data.get("findings", [])
            for d in items:
                out.append(Result(kind="xss", target=d.get("data", d.get("url","")), severity="high", raw=d))
        except Exception:
            pass
        return out
