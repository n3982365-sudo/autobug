from celery import chain
from orchestrator.tasks.recon import passive_recon, asset_dedup, asset_graph, osint_recon
from orchestrator.tasks.active import active_recon, live_hosts, tech_fingerprint
from orchestrator.tasks.vuln import vuln_scan, finding_dedup, severity_triage
from orchestrator.tasks.exploit import exploit_verify
from orchestrator.tasks.screenshot import capture_screenshots
from orchestrator.tasks.report import report_generate
from orchestrator.tasks.notify import notify_summary

MODES = {
    1: chain(passive_recon.s(), asset_dedup.s(), asset_graph.s(), notify_summary.s()),
    2: chain(passive_recon.s(), asset_dedup.s(), active_recon.s(), live_hosts.s(),
             tech_fingerprint.s(), notify_summary.s()),
    3: chain(passive_recon.s(), asset_dedup.s(), asset_graph.s(),
             active_recon.s(), live_hosts.s(), tech_fingerprint.s(),
             osint_recon.s(), vuln_scan.s(), finding_dedup.s(), severity_triage.s(),
             exploit_verify.s(), capture_screenshots.s(), report_generate.s(), notify_summary.s()),
}

def launch(scan_id: int, mode: int):
    return MODES[mode].apply_async(args=[scan_id])
