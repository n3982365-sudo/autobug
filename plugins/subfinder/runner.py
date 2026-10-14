import tempfile, subprocess
from plugins.runner_base import PluginBase
from plugins._schema import Result

class Plugin(PluginBase):
    def run(self, target: str, **kw):
        wd = tempfile.mkdtemp(prefix="autobug_subfinder_")
        cmd = f"docker run --rm -v {wd}:/out projectdiscovery/subfinder:latest -d {target} -silent -o /out/hosts.txt"
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=600)
        return wd, out.stdout, out.stderr
    def parse(self, workdir: str) -> list[Result]:
        try:
            lines = open(f"{workdir}/hosts.txt").read().splitlines()
        except Exception:
            return []
        return [Result(kind="subdomain", target=h.strip(), severity="info") for h in lines if h.strip()]
