#!/usr/bin/env python3
"""Run the same OpenRouter chat request against the shortlisted free models."""

import argparse
import concurrent.futures
import json
import time
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "api.env.json"
MODELS = [
    "nvidia/nemotron-3.5-super-vl:free",
    "thinkingmachines/inkling-small:free",
    "minimax/minimax-m3.1-flash:free",
]
DEFAULT_PROMPT = (
    "Analyze this hypothetical setup: a EUR/USD 15-minute candle closes above "
    "the prior day's high, then the next candle falls back below that level "
    "on low volume. In 2-3 sentences, explain what this suggests and whether "
    "the breakout is confirmed. Do not invent prices or claim live data."
)


def load_config():
    if not CONFIG_PATH.exists():
        raise SystemExit(
            f"Missing {CONFIG_PATH.name}; copy api.env.json.example and set "
            "LLM_BASE_URL and LLM_API_KEY first."
        )
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8-sig"))
    api_key = config.get("LLM_API_KEY", "").strip()
    if not api_key:
        raise SystemExit(f"LLM_API_KEY is empty in {CONFIG_PATH.name}.")
    base_url = config.get("LLM_BASE_URL", "https://openrouter.ai/api/v1")
    return base_url.rstrip("/"), api_key


def extract_error(raw_body):
    try:
        payload = json.loads(raw_body)
        error = payload.get("error", {})
        if isinstance(error, dict):
            return str(error.get("message") or error)
        return str(error)
    except (json.JSONDecodeError, TypeError):
        return raw_body.strip() or "No error details returned."


def request_model(model, prompt, base_url, api_key, max_tokens):
    endpoint = f"{base_url}/chat/completions"
    body = json.dumps(
        {
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
            "temperature": 0.2,
            "stream": False,
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            payload = json.loads(response.read().decode("utf-8"))
            elapsed_ms = round((time.perf_counter() - started) * 1000)
            choice = (payload.get("choices") or [{}])[0]
            message = choice.get("message") or {}
            text = message.get("content")
            if isinstance(text, list):
                text = " ".join(
                    str(part.get("text", ""))
                    for part in text
                    if isinstance(part, dict)
                )
            if not text:
                text = message.get("reasoning") or message.get("reasoning_content")
                if text:
                    text = f"[No final content; reasoning returned] {text}"
            usage = payload.get("usage") or {}
            return {
                "model": model,
                "http": response.status,
                "latency_ms": elapsed_ms,
                "finish": choice.get("finish_reason", "unknown"),
                "tokens": usage.get("total_tokens", "unknown"),
                "response": str(text or "[Empty response]"),
            }
    except urllib.error.HTTPError as error:
        elapsed_ms = round((time.perf_counter() - started) * 1000)
        details = extract_error(error.read().decode("utf-8", errors="replace"))
        return {
            "model": model,
            "http": error.code,
            "latency_ms": elapsed_ms,
            "finish": "error",
            "tokens": "-",
            "response": details,
        }
    except Exception as error:  # report network/timeout failures per model
        elapsed_ms = round((time.perf_counter() - started) * 1000)
        return {
            "model": model,
            "http": "ERR",
            "latency_ms": elapsed_ms,
            "finish": "error",
            "tokens": "-",
            "response": str(error),
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prompt", default=DEFAULT_PROMPT)
    parser.add_argument("--max-tokens", type=int, default=512)
    parser.add_argument("--models", nargs="+", default=MODELS)
    args = parser.parse_args()
    base_url, api_key = load_config()

    print(f"Testing {len(args.models)} models concurrently against {base_url}")
    results = []
    with concurrent.futures.ThreadPoolExecutor(
        max_workers=len(args.models)
    ) as executor:
        futures = {
            executor.submit(
                request_model,
                model,
                args.prompt,
                base_url,
                api_key,
                args.max_tokens,
            ): model
            for model in args.models
        }
        for future in concurrent.futures.as_completed(futures):
            results.append(future.result())

    for result in results:
        print(
            f"\n{result['model']} | HTTP {result['http']} | "
            f"{result['latency_ms']} ms | finish={result['finish']} | "
            f"tokens={result['tokens']}"
        )
        print(result["response"])


if __name__ == "__main__":
    main()
