import subprocess, tempfile, os, httpx, json

def run(url_or_path: str) -> dict:
    out = {"input": url_or_path, "type": "image", "sources": [], "data": {}}
    tmp = None
    try:
        if url_or_path.startswith("http"):
            tmp = tempfile.NamedTemporaryFile(suffix=".img", delete=False).name
            r = httpx.get(url_or_path, timeout=20)
            open(tmp, "wb").write(r.content)
        else:
            tmp = url_or_path
        try:
            meta = subprocess.run(["exiftool", "-json", tmp], capture_output=True, text=True, timeout=20)
            if meta.returncode == 0:
                out["data"]["exif"] = json.loads(meta.stdout)
                out["sources"].append("exiftool")
        except Exception:
            pass
        try:
            ocr = subprocess.run(["tesseract", tmp, "stdout"], capture_output=True, text=True, timeout=30)
            if ocr.returncode == 0 and ocr.stdout.strip():
                out["data"]["ocr_text"] = ocr.stdout.strip()
                out["sources"].append("tesseract")
        except Exception:
            pass
    finally:
        if tmp and tmp.startswith(tempfile.gettempdir()) and os.path.exists(tmp):
            os.unlink(tmp)
    return out
