---
name: biquote-api
description: >-
  Expert guide and reference for integrating with the Biquote Real-Time Market Data API (https://biquote.io/docs/).
  Use this skill whenever building financial charts, price trackers, tickers, alert monitors, or trading apps requiring
  live Forex, Gold/Metals, Cryptocurrencies, and Index CFDs over REST or SignalR WebSocket streaming.
---

# Biquote Real-Time Market Data API Skill

The **Biquote API** (https://biquote.io) provides live tick data (bid, ask, mid, spread), OHLC candlesticks, a 54-country macroeconomic calendar, market movers, financial news, and 12 embeddable widgets over REST and SignalR WebSocket streaming.

- **Base URL**: `https://biquote.io`
- **Authentication**: **None** (100% free, no API keys, no sign-up, open CORS for direct browser/app usage).
- **Rate Limit**: **15,000 requests/minute per IP** (unmetered on WebSocket/SignalR).
- **Feed Source**: MetaTrader 5 (MT5) broker feed and Matriks.

---

## 1. Quick Decision Matrix: What to Call

| What You Are Building | Correct Approach | DO NOT USE (Anti-Pattern) |
|---|---|---|
| **Live price ticker, dashboard, or alert monitor** | SignalR Hub: `/hubs/tick` | Polling REST loop with `?t=${Date.now()}` |
| **Multiple symbols on screen** | `GET /api/latest?symbols=A&symbols=B` | Loop calling `GET /api/{symbol}` per ticker |
| **Chart / Candlesticks** | `GET /api/{symbol}/ohlc` | Stitching raw ticks together manually |
| **One-off price check** | `GET /api/{symbol}` | Heavy history endpoints |
| **Instrument picker / search / dropdown** | `GET /api/symbols?quotedWithinDays=7` | `liveOnly=true` (empties on weekends!) |
| **Economic releases** | `GET /api/calendar?importance=high` | Unfiltered calls (too noisy) |
| **Drop-in Web Widgets** | `<div data-biquote-widget="...">` | Building custom charts/tickers from scratch |

---

## 2. The 7 Critical Anti-Patterns & Gotchas

### 1. Markets Close — Check `marketState` and `stale`
- Forex stops quoting Friday night to Sunday night; equities close daily.
- A closed market returns **HTTP 200 with the last-known price**, `marketState: "closed"`, and `stale: true`.
- **UI Rule**: Render as *"Market closed — last price"*. Hide or gray out the day-change percentage (it belongs to an ended session).
- **Trading Clients**: Pass `allowStale=false` to enforce HTTP 404 when quotes are older than 5 minutes.

### 2. CFD Pricing: `last` and `volume` are ALWAYS `0`
- Biquote streams OTC broker quotes, not a consolidated exchange tape.
- **Always use `mid`** (or `(bid + ask) / 2`). Never display or compute against `last` or `volume`.

### 3. Timestamp Trap: Parse `timestamp`, NOT `time`
- `timestamp`: ISO 8601 UTC string (`2026-02-24T10:30:00Z`). **Always parse this.**
- `time`: MetaTrader legacy format (`2026.02.24 10:30:00`). Incompatible with standard date parsers.

### 4. Repeated Query Parameters for Batching
- Multi-symbol queries MUST repeat the key:
  - ✅ `?symbols=EURUSD&symbols=XAUUSD&symbols=BTCUSD`
  - ❌ `?symbols=EURUSD,XAUUSD` (commas do NOT work; parsed as one symbol)

### 5. OHLC Bars Arrive NEWEST-FIRST
- `GET /api/{symbol}/ohlc` returns `{ symbol, interval, bars: [...] }`.
- `bars[0]` is the **newest** bar. Always **reverse the array** before feeding it to charting libraries.
- The in-progress bar has `isOpen: true`.

### 6. Do Not Poll REST for Live Updates
- REST polling wastes resources and risks 429 rate limits.
- Connect to the **SignalR Hub** at `https://biquote.io/hubs/tick`. It is **unmetered** and pushes instant updates.

### 7. Pickers Require `quotedWithinDays=7`
- Out of ~1,700 listed symbols, ~305 have quoted recently.
- Filtering by `isActive=true` returns dead catalogue items.
- Filtering by `liveOnly=true` returns 0 items over weekends.
- Use `GET /api/symbols?quotedWithinDays=7`.

---

## 3. SignalR Real-Time Streaming (`/hubs/tick`)

### Connection Setup:
- **Hub URL**: `https://biquote.io/hubs/tick`
- **Client libraries**:
  - JS/Node: `@microsoft/signalr`
  - Python: `pysignalr`
  - .NET: `Microsoft.AspNetCore.SignalR.Client`
  - Flutter/Dart: `signalr_netcore`

### Client Invocation:
```javascript
await connection.invoke('Subscribe', ['EURUSD', 'XAUUSD', 'BTCUSD']);
await connection.invoke('Unsubscribe', ['EURUSD']);
const tick = await connection.invoke('GetLatestTick', 'EURUSD');
const currentList = await connection.invoke('GetSubscriptions');
```

### Event Handlers:
- `ReceiveTick(tick)`: Fired on every price update and once as a seed immediately upon subscribing.
- `ReceiveSubscriptionState(states)`: Returns `[{ symbol, state: "open"|"closed"|"unknown", seeded }]`. Use `state === "unknown"` to detect invalid tickers.

---

## 4. REST Endpoints Summary

For complete query parameters, responses, and curl commands, see [endpoints.md](./references/endpoints.md).

- **Ticks**:
  - `GET /api/{symbol}`: Latest single quote (`allowStale=true|false`).
  - `GET /api/latest`: Batch quotes (`?symbols=A&symbols=B`).
  - `GET /api/{symbol}/history`: Raw tick history (`count=1..1000`).
  - `GET /api/active`: Symbols currently streaming ticks.
- **Symbols**:
  - `GET /api/symbols`: Filtered catalog (`quotedWithinDays=7`, `type`, `source`).
  - `GET /api/symbols/{name}`: Metadata for one ticker.
  - `GET /api/symbols/search`: Keyword search (`?q=gold`).
- **Candlesticks**:
  - `GET /api/{symbol}/ohlc`: Candlesticks (`interval=1m,5m,15m,30m,1h,4h,1d`, `limit=1..1000`).
- **Market Movers**:
  - `GET /api/market/gainers`: Top percentage gainers.
  - `GET /api/market/losers`: Top percentage losers.
  - `GET /api/market/most-active`: Highest intraday volatility `(high - low) / mid`.
  - `GET /api/market/summary`: Total counts by asset class.
- **Economic Calendar**:
  - `GET /api/calendar`: Range filter (`from`, `to`, `countries`, `importance`, `type`).
  - `GET /api/calendar/upcoming`: Next upcoming announcements (`limit`, `importance`).
  - `GET /api/calendar/countries`: Supported countries list.
  - `GET /api/calendar/{eventId}/history`: Print history for a series (e.g. `mql5:840`).
- **News**:
  - `GET /api/news/market`: Aggregated market news (`symbol`, `language`, `country`).
  - `GET /api/news/hn`: Hacker News financial posts (`q`, `maxResults`).
- **Health**:
  - `GET /health`: Service and feed status.

---

## 5. Detailed Guides & Competitor Comparisons

Explore the in-depth guides in `references/guides/`:

- **[mt5_bridge.md](./references/guides/mt5_bridge.md)**: MetaTrader 5 architecture, replacing local VPS/EAs, mapping `CopyRates()` and `OnTick()`, and symbol universe.
- **[python_integration.md](./references/guides/python_integration.md)**: Python integration guide with official `biquote` SDK, raw requests tuples, pandas OHLC parsing, and async `pysignalr` streaming.
- **[widgets.md](./references/guides/widgets.md)**: Complete guide to the 12 embeddable widgets, attributes, 1.4KB loader, iframe fallbacks for strict CSP, and custom themes.
- **[competitor_comparison.md](./references/guides/competitor_comparison.md)**: Side-by-side matrices comparing Biquote with Alpha Vantage (25 req/day cap), TwelveData (credit meters), and Finnhub (paywalled FX).
- **[architecture_and_cost.md](./references/guides/architecture_and_cost.md)**: Telemetry study of 13.8M req/day traffic, client concentration, 141MB container footprint, Redis caching, and rate limiting philosophy.

---

## 6. Code Assets & Reference Implementations

- **[models.md](./references/models.md)**: Complete JSON schemas and field definitions.
- **[endpoints.md](./references/endpoints.md)**: Comprehensive query parameters and headers reference.
- **[signalr.md](./references/signalr.md)**: Complete SignalR protocol lifecycle, reconnection handling, and streaming architecture.
- **[calendar.md](./references/calendar.md)**: Guide to 54-country economic calendar, null vs 0 handling, and units.
- **[flutter_biquote_service.dart](./examples/flutter_biquote_service.dart)**: Production-ready Flutter / Dart service implementation.
- **[signalr_client.mjs](./examples/signalr_client.mjs)**: JavaScript Node.js / Browser client with automatic reconnect.
- **[python_client.py](./examples/python_client.py)**: Python client using requests, pandas, and `pysignalr`.
- **[widget_embed_example.html](./examples/widget_embed_example.html)**: Ready-to-use HTML template demonstrating all embeddable widgets.
