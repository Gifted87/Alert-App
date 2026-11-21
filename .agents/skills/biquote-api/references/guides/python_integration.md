# Python Integration Guide for Biquote API

Source: https://biquote.io/guides/free-forex-api-python.html

## 1. Quick Setup & Installation

You can access Biquote either via direct HTTP requests (`requests` / `httpx`) or using the official SDK:

```bash
pip install biquote requests pandas pysignalr
```

---

## 2. Reading Quotes

### Option A: Official Python SDK (`biquote`)
```python
from biquote import Biquote

bq = Biquote()

# Single quote
tick = bq.tick("EURUSD")
print(f"EURUSD Mid: {tick['mid']}")

# Batch quotes (multi-symbol)
quotes = bq.latest(["EURUSD", "XAUUSD", "BTCUSD"])
for sym, t in quotes.items():
    print(f"{sym}: {t['mid']}")
```

### Option B: Raw Requests (Correct Batch Format)
In Python `requests`, to send repeated parameters without commas, supply a list of tuples:
```python
import requests

params = [("symbols", s) for s in ("EURUSD", "XAUUSD", "BTCUSD", "USDTRY")]
res = requests.get("https://biquote.io/api/latest", params=params).json()

for sym, t in res.items():
    print(f"{sym:8} {t['mid']:>12} {t['dayDiffPercent']:+.2f}%")
```

---

## 3. Candlesticks (OHLC) into Pandas DataFrames

Biquote delivers candles in an envelope: `{ symbol, interval, bars: [...] }`.
Bars are ordered **newest-first** (index 0 is latest/forming bar).

```python
import requests
import pandas as pd

res = requests.get(
    "https://biquote.io/api/XAUUSD/ohlc",
    params={"interval": "1h", "limit": 500}
).json()

df = pd.DataFrame(res["bars"])
df["openTime"] = pd.to_datetime(df["openTime"])

# Sort index chronologically (oldest to newest)
df = df.set_index("openTime").sort_index()

# Filter out the unclosed candle if calculating closed-bar indicators
closed_candles = df[~df["isOpen"]]

print(df[["open", "high", "low", "close", "tickVolume"]].tail())
```

Supported intervals: `1m`, `5m`, `15m`, `30m`, `1h`, `4h`, `1d`.

---

## 4. Real-Time Streaming in Python with `pysignalr`

SignalR push streaming avoids REST polling and does not count toward the 15,000 req/min rate limit:

```python
import asyncio
from pysignalr.client import SignalRClient

async def run_market_stream():
    client = SignalRClient("https://biquote.io/hubs/tick")

    # Handle incoming ticks
    client.on("ReceiveTick", lambda tick_wrapper: print(
        f"⚡ TICK: {tick_wrapper[0]['symbol']} Mid={tick_wrapper[0]['mid']}"
    ))

    # Subscribe once socket opens
    client.on_open(lambda: client.send("Subscribe", [["EURUSD", "XAUUSD", "BTCUSD"]]))

    await client.run()

if __name__ == "__main__":
    asyncio.run(run_market_stream())
```

---

## 5. Detecting Market Closed State

Markets (especially Forex) close from Friday night to Sunday night UTC:

```python
import requests

tick = requests.get("https://biquote.io/api/EURUSD").json()

if tick.get("marketState") == "closed":
    hours_ago = tick.get("quoteAgeSeconds", 0) // 3600
    print(f"EURUSD: {tick['mid']} (Market Closed, last quote {hours_ago}h ago)")
else:
    print(f"EURUSD: {tick['mid']} (Live, {tick['dayDiffPercent']:+.2f}%)")
```
*Note: For automated trading systems, pass `allowStale=false` in the query to receive HTTP 404 when quotes are older than 5 minutes.*
