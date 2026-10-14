def build(input_type: str, value: str, results: dict) -> dict:
    return {"input_type": input_type, "input_value": value,
            "sources": results.get("sources", []),
            "raw": results}
