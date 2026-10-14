import tempfile, subprocess, json
from plugins.runner_base import PluginBase
from plugins._schema import Result

class Plugin(PluginBase):
    def run(self, target: str, **kw):
        wd = tempfile.mkdtemp(prefix="autobug_nuclei_")
        cmd = f"docker run --rm -v {wd}:/out projectdiscovery/nuclei:latest -u {target} -silent -jsonl -o /out/findings.json -severity critical,high,medium,low,info"
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=1800)
        return wd, out.stdout, out.stderr
    def parse(self, workdir: str) -> list[Result]:
        out: list[Result] = []
        try:
            for line in open(f"{workdir}/findings.json"):
                d = json.loads(line)
                info = d.get("info", {})
                out.append(Result(kind=d.get("template-id","nuclei"),
                                  target=d.get("matched-at", d.get("host","")),
                                  severity=info.get("severity","info"), raw=d))
        except Exception:
            pass
        return out
