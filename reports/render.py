import os
from jinja2 import Environment, FileSystemLoader
from api.storage import put_object

HERE = os.path.dirname(__file__)
env = Environment(loader=FileSystemLoader(os.path.join(HERE, "templates")))

def render_report(scan, findings) -> str:
    template = env.get_template("report.html.j2")
    html = template.render(scan=scan, findings=findings, counts=_counts(findings))
    out_dir = os.path.join(os.getenv("DATA_DIR", "/app/data"), "reports")
    os.makedirs(out_dir, exist_ok=True)
    html_path = os.path.join(out_dir, f"scan_{scan.id}.html")
    with open(html_path, "w") as f:
        f.write(html)
    pdf_path = os.path.join(out_dir, f"scan_{scan.id}.pdf")
    try:
        from weasyprint import HTML
        HTML(string=html).write_pdf(pdf_path)
    except Exception:
        pdf_path = html_path
    for p in [html_path, pdf_path]:
        if os.path.exists(p):
            try:
                put_object(f"scans/{scan.id}/report/{os.path.basename(p)}", p)
            except Exception:
                pass
    return pdf_path

def _counts(findings):
    c: dict[str, int] = {}
    for f in findings:
        c[f.severity] = c.get(f.severity, 0) + 1
    return c
