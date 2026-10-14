import importlib.util
from pathlib import Path
import yaml
from plugins._schema import Manifest

ROOT = Path(__file__).parent

class Registry:
    def __init__(self):
        self.plugins: dict[str, Manifest] = {}
        self._load()
    def _load(self):
        for mf in ROOT.glob("*/manifest.yaml"):
            try:
                data = yaml.safe_load(mf.read_text())
                m = Manifest(**data)
                if m.enabled:
                    self.plugins[m.name] = m
            except Exception:
                continue
    def get(self, name: str) -> Manifest | None:
        return self.plugins.get(name)
    def by_category(self, cat: str) -> list[Manifest]:
        return [p for p in self.plugins.values() if p.category == cat]
    def all(self) -> list[Manifest]:
        return list(self.plugins.values())
    def load_runner(self, name: str):
        path = ROOT / name / "runner.py"
        if not path.exists(): return None
        spec = importlib.util.spec_from_file_location(f"plugin_{name}", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod

registry = Registry()
