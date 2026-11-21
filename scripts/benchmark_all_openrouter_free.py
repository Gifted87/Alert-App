#!/usr/bin/env python3
"""Fetch and benchmark every free text model listed by OpenRouter.

Reads the OpenRouter API key from the ignored project-root api.env.json, sends
the same chat completion request to each model using a multiprocessing pool,
and writes CSV/JSON reports beside this script's parent directory.
"""

import argparse
import concurrent.futures
import csv
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "api.env.json"
CSV_PATH = ROOT / "openrouter_free_model_benchmark.csv"
JSON_PATH = ROOT / "openrouter_free_model_benchmark.json"
DEFAULT_PROMPT = (
    "Assess this hypothetical setup: price closes above resistance, then the "
    "next candle falls back below it on declining volume. In 1-2 sentences, "
    "say whether the breakout is confirmed and why. Do not invent data."
)
CSV_FIELDS = [
    "model_id",
    "name",
    "parameter_count",
    "parameter_source",
    "context_length",
    "http_status",
    "latency_ms",
    "finish_reason",
    "total_tokens",
    "response",
    "error",
]


def load_config():
    if not CONFIG_PATH.is_file():
        raise SystemExit(
            f"Missing {CONFIG_PATH.name}. Copy api.env.json.example and set "
            "LLM_BASE_URL and LLM_API_KEY."
        )
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8-sig"))
    base_url = config.get("LLM_BASE_URL", "").strip().rstrip("/")
    api_key = config.get("LLM_API_KEY", "").strip()
    if "openrouter.ai" not in base_url:
        raise SystemExit("LLM_BASE_URL in api.env.json must point to OpenRouter.")
    if not api_key:
        raise SystemExit(f"LLM_API_KEY is empty in {CONFIG_PATH.name}.")
    return base_url, api_key


def http_json(url, api_key, *, payload=None, timeout=60):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {"Authorization": f"Bearer {api_key}", "Accept": "application/json"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=body, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        try:
            data = json.loads(detail)
            detail = str((data.get("error") or {}).get("message") or data)
        except (json.JSONDecodeError, AttributeError):
            pass
        return error.code, {"error": detail}


def catalog_models(base_url, api_key):
    models = []
    offset = 0
    page_size = 1000
    while True:
        query = urllib.parse.urlencode(
            {
                "limit": page_size,
                "offset": offset,
                "output_modalities": "text",
                "input_modalities": "text",
                "sort": "throughput-high-to-low",
            }
        )
        status, payload = http_json(
            f"{base_url}/models?{query}", api_key, timeout=60
        )
        if status != 200:
            raise SystemExit(
                f"OpenRouter model catalog returned HTTP {status}: "
                f"{payload.get('error', 'unknown error')}"
            )
        page = payload.get("data") or []
        models.extend(page)
        if len(page) < page_size:
            break
        offset += len(page)

    free = []
    for model in models:
        pricing = model.get("pricing") or {}
        try:
            prompt_price = float(pricing.get("prompt", "inf"))
            completion_price = float(pricing.get("completion", "inf"))
            request_price = float(pricing.get("request", 0) or 0)
        except (TypeError, ValueError):
            continue
        if prompt_price == 0 and completion_price == 0 and request_price == 0:
            free.append(model)
    return free


def parameter_count(model):
    """Return catalog-reported or clearly marked name/description estimate."""
    for key in ("parameter_count", "parameters", "num_parameters"):
        value = model.get(key)
        if isinstance(value, (int, float)) and value > 0:
            return f"{value:,}", "OpenRouter catalog"
        if isinstance(value, str) and value.strip():
            return value.strip(), "OpenRouter catalog"

    text = " ".join(
        str(model.get(key) or "") for key in ("description", "name", "id")
    )
    patterns = [
        re.compile(
            r"(?P<active>\d+(?:\.\d+)?)\s*B\s*active(?:\s+parameters?)?"
            r".*?(?P<total>\d+(?:\.\d+)?)\s*B\s*total",
            re.IGNORECASE,
        ),
        re.compile(
            r"(?P<total>\d+(?:\.\d+)?)\s*B\s*total"
            r".*?(?P<active>\d+(?:\.\d+)?)\s*B\s*active",
            re.IGNORECASE,
        ),
    ]
    for pattern in patterns:
        match = pattern.search(text)
        if match:
            return (
                f"{match.group('active')}B active / {match.group('total')}B total",
                "OpenRouter description",
            )

    parameter_phrase = re.search(
        r"(\d+(?:\.\d+)?)\s*(?:B|billion)\s*(?:dense\s+)?parameters?",
        text,
        re.IGNORECASE,
    )
    if parameter_phrase:
        return f"{parameter_phrase.group(1)}B", "OpenRouter description"

    name = f"{model.get('name', '')} {model.get('id', '')}"
    size_matches = re.findall(
        r"(?<![A-Za-z0-9])(\d+(?:\.\d+)?)\s*B(?=\b|[-_])",
        name,
        re.IGNORECASE,
    )
    if size_matches:
        return f"{size_matches[0]}B", "inferred from model name"
    return "Unknown", "not published in OpenRouter catalog"


def response_text(message):
    content = message.get("content")
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = []
        for part in content:
            if isinstance(part, dict) and part.get("text"):
                parts.append(str(part["text"]))
        return " ".join(parts).strip()
    reasoning = message.get("reasoning") or message.get("reasoning_content")
    if reasoning:
        return f"[No final content; reasoning returned] {reasoning}"
    return "[Empty response]"


def benchmark_one(args):
    model, base_url, api_key, prompt, max_tokens, timeout = args
    model_id = str(model.get("id", "unknown"))
    size, size_source = parameter_count(model)
    parameters = model.get("supported_parameters") or []
    payload = {
        "model": model_id,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "stream": False,
    }
    if "temperature" in parameters:
        payload["temperature"] = 0.2
    started = time.perf_counter()
    status, result = http_json(
        f"{base_url}/chat/completions",
        api_key,
        payload=payload,
        timeout=timeout,
    )
    latency_ms = round((time.perf_counter() - started) * 1000)
    error = ""
    content = ""
    finish_reason = ""
    total_tokens = ""
    returned_model = model_id
    if status == 200:
        choices = result.get("choices") or []
        if choices:
            choice = choices[0]
            finish_reason = str(choice.get("finish_reason") or "")
            content = response_text(choice.get("message") or {})
        usage = result.get("usage") or {}
        total_tokens = usage.get("total_tokens", "")
        returned_model = str(result.get("model") or model_id)
    else:
        error = str(result.get("error") or "Request failed")

    # Guard against an upstream error body ever echoing the bearer token.
    error = error.replace(api_key, "[redacted]")
    content = content.replace(api_key, "[redacted]")
    return {
        "model_id": model_id,
        "name": str(model.get("name") or returned_model),
        "parameter_count": size,
        "parameter_source": size_source,
        "context_length": model.get("context_length", ""),
        "http_status": status,
        "latency_ms": latency_ms,
        "finish_reason": finish_reason,
        "total_tokens": total_tokens,
        "response": content,
        "error": error,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--max-tokens", type=int, default=256)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--prompt", default=DEFAULT_PROMPT)
    parser.add_argument("--csv", type=Path, default=CSV_PATH)
    parser.add_argument("--json", type=Path, default=JSON_PATH)
    args = parser.parse_args()
    if args.workers < 1:
        parser.error("--workers must be at least 1")

    base_url, api_key = load_config()
    models = catalog_models(base_url, api_key)
    print(
        f"Found {len(models)} text models with zero prompt, completion, and "
        f"request price. Testing with {args.workers} worker processes.",
        flush=True,
    )
    args.csv.parent.mkdir(parents=True, exist_ok=True)
    args.json.parent.mkdir(parents=True, exist_ok=True)
    tasks = [
        (model, base_url, api_key, args.prompt, args.max_tokens, args.timeout)
        for model in models
    ]
    results = []
    with args.csv.open("w", newline="", encoding="utf-8-sig") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=CSV_FIELDS)
        writer.writeheader()
        csv_file.flush()
        with concurrent.futures.ProcessPoolExecutor(
            max_workers=args.workers
        ) as executor:
            futures = [executor.submit(benchmark_one, task) for task in tasks]
            for future in concurrent.futures.as_completed(futures):
                row = future.result()
                results.append(row)
                writer.writerow(row)
                csv_file.flush()
                print(
                    f"[{len(results)}/{len(models)}] HTTP {row['http_status']} "
                    f"{row['latency_ms']} ms | {row['parameter_count']} | "
                    f"{row['model_id']}",
                    flush=True,
                )

    results.sort(
        key=lambda row: (
            row["http_status"] != 200,
            row["latency_ms"] if isinstance(row["latency_ms"], int) else 0,
        )
    )
    report = {
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "catalog_endpoint": f"{base_url}/models",
        "tested_models": len(models),
        "workers": args.workers,
        "max_tokens": args.max_tokens,
        "prompt": args.prompt,
        "parameter_count_note": (
            "OpenRouter does not publish a numeric parameter-count field for "
            "every model. Counts parsed from a model name are marked inferred; "
            "unknown means no count was present in catalog metadata."
        ),
        "results": results,
    }
    args.json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    successes = sum(row["http_status"] == 200 for row in results)
    failures = len(results) - successes
    print(
        f"\nCompleted: {successes} succeeded, {failures} failed.\n"
        f"CSV: {args.csv}\nJSON: {args.json}",
        flush=True,
    )


if __name__ == "__main__":
    main()
