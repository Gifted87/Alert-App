"""
Biquote API Python Client Example
Uses both the official `biquote` SDK, direct `requests` HTTP calls, and `pysignalr` WebSocket streaming.
Install: pip install biquote requests pandas pysignalr
"""

import asyncio
import requests
import pandas as pd

BASE_URL = "https://biquote.io"

def fetch_batch_quotes(symbols):
    """
    Fetch multiple symbols in ONE request using repeated query parameters.
    (Commas are not supported).
    """
    # Repeated parameter tuples
    params = [("symbols", s) for s in symbols]
    resp = requests.get(f"{BASE_URL}/api/latest", params=params)
    resp.raise_for_status()
    data = resp.json()
    
    for symbol, tick in data.items():
        # Check marketState: closed markets return 200 with last known price
        if tick.get("marketState") == "closed":
            hours_ago = tick.get("quoteAgeSeconds", 0) // 3600
            print(f"[CLOSED] {symbol:8}: Last Mid={tick.get('mid')} (quited {hours_ago}h ago)")
        else:
            mid = tick.get("mid", 0.0)
            pct = tick.get("dayDiffPercent", 0.0)
            print(f"[LIVE]   {symbol:8}: Mid={mid:<10} Change={pct:+.2f}%")
    return data

def fetch_candles_dataframe(symbol, interval="1h", limit=100):
    """
    Fetch OHLC candles and format into a pandas DataFrame (oldest-first).
    """
    resp = requests.get(f"{BASE_URL}/api/{symbol}/ohlc", params={"interval": interval, "limit": limit})
    resp.raise_for_status()
    data = resp.json()
    
    # Envelope contains: { symbol, interval, bars: [...] }
    # Bars arrive newest-first from the API -> sort/reverse chronologically
    bars = data.get("bars", [])
    df = pd.DataFrame(bars)
    
    if not df.empty:
        df["openTime"] = pd.to_datetime(df["openTime"])
        df = df.set_index("openTime").sort_index()
    return df

def fetch_calendar(countries="US,EU,TR", importance="high"):
    """
    Fetch economic calendar releases. Note: null values must never be coerced to 0.
    """
    resp = requests.get(f"{BASE_URL}/api/calendar", params={
        "countries": countries,
        "importance": importance,
        "limit": 50
    })
    resp.raise_for_status()
    events = resp.json()
    
    print(f"\nFetched {len(events)} economic events:")
    for e in events[:10]:
        actual = "PENDING" if e["actual"] is None else f"{e['actual']}{e.get('unit','')}"
        forecast = "-" if e["forecast"] is None else f"{e['forecast']}{e.get('unit','')}"
        print(f"{e['time'][:16]} | {e['countryCode']:2} | {e['name'][:28]:<28} | Act: {actual:<10} | Fst: {forecast}")

async def stream_ticks_pysignalr():
    """
    Continuous streaming via unmetered SignalR WebSocket (bypasses 15,000 req/min REST quota).
    """
    try:
        from pysignalr.client import SignalRClient
    except ImportError:
        print("pysignalr not installed. Run: pip install pysignalr")
        return

    client = SignalRClient("https://biquote.io/hubs/tick")

    # Subscribe to EURUSD, XAUUSD, BTCUSD
    client.on_open(lambda: client.send("Subscribe", [["EURUSD", "XAUUSD", "BTCUSD"]]))

    # Handle live tick pushes
    client.on("ReceiveTick", lambda tick_wrapper: print(
        f"⚡ STREAM: {tick_wrapper[0]['symbol']} -> Mid: {tick_wrapper[0]['mid']}"
    ))

    print("\nStarting SignalR stream (Press Ctrl+C to stop)...")
    await client.run()

if __name__ == "__main__":
    print("=== 1. Batch Latest Quotes ===")
    fetch_batch_quotes(["EURUSD", "XAUUSD", "BTCUSD", "USDTRY"])
    
    print("\n=== 2. Hourly Candles into DataFrame ===")
    df = fetch_candles_dataframe("XAUUSD", interval="1h", limit=10)
    print(df[["open", "high", "low", "close", "tickVolume"]])
    
    print("\n=== 3. High Impact Economic Calendar ===")
    fetch_calendar()
