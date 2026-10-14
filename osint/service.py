from osint.sources import email as s_email, domain as s_domain, phone as s_phone, image as s_image

HANDLERS = {"email": s_email.run, "domain": s_domain.run, "phone": s_phone.run, "image": s_image.run}

def run(input_type: str, value: str) -> dict:
    fn = HANDLERS.get(input_type)
    if not fn:
        return {"error": f"unknown type {input_type}", "sources": []}
    return fn(value)

def run_domain_osint(domain: str) -> dict:
    return s_domain.run(domain)
