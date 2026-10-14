import subprocess, tempfile
from jinja2 import Template
from plugins._schema import Manifest, Result

class PluginBase:
    manifest: Manifest
    def __init__(self, manifest: Manifest):
        self.manifest = manifest
    def build_command(self, **kwargs) -> str:
        return Template(self.manifest.command).render(**kwargs)
    def run(self, timeout: int | None = None, **kwargs) -> tuple[str, str, str]:
        workdir = tempfile.mkdtemp(prefix=f"autobug_{self.manifest.name}_")
        cmd = self.build_command(workdir=workdir, **kwargs)
        t = timeout or self.manifest.timeout
        proc = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=t, cwd=workdir)
        return workdir, proc.stdout, proc.stderr
    def parse(self, workdir: str) -> list[Result]:
        raise NotImplementedError
