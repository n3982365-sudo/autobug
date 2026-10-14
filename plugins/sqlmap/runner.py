import tempfile, subprocess, glob
from plugins.runner_base import PluginBase
from plugins._schema import Result

class Plugin(PluginBase):
    def run(self, target: str, **kw):
        wd = tempfile.mkdtemp(prefix="autobug_sqlmap_")
        cmd = f'docker run --rm -v {wd}:/out googlesecurity/sqlmap:latest -u "{target}" --batch --level=2 --risk=2 --output-dir=/out --flush-session'
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=1800)
        return wd, out.stdout, out.stderr
    def parse(self, workdir: str) -> list[Result]:
        out: list[Result] = []
        for log in glob.glob(f"{workdir}/**/log", recursive=True):
            try:
                txt = open(log, errors="ignore").read()
            except Exception:
                continue
            if "is vulnerable" in txt or "Parameter:" in txt:
                out.append(Result(kind="sqli", target=workdir, severity="high", raw={"log": log}))
        return out
