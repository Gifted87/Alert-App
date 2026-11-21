# MetaTrader 5 (MT5) Feed & REST/WebSocket Bridge

Source: https://biquote.io/guides/metatrader5-data-api.html

## 1. Overview & Architecture

Getting live prices and historical candlesticks out of MetaTrader 5 traditionally requires significant operational overhead:
- Running a dedicated Windows VPS 24/7.
- Maintaining an active logged-in terminal session with broker credentials.
- Writing custom MQL5 Expert Advisors (EAs).
- Wiring up Windows named pipes, sockets, or the Windows-only MetaTrader5 Python package.

**Biquote's Architecture**:
Biquote runs this infrastructure server-side using an MQL5 Expert Advisor pushing raw tick data over low-latency sockets into a high-performance C# / Redis ingestion engine, exposing the feed as standard HTTP REST and SignalR WebSockets.

---

## 2. Feature Mapping: MQL5 Terminal vs. Biquote API

| MQL5 Native Mechanism | Biquote HTTP/WebSocket Equivalent | Advantages |
|---|---|---|
| **`SymbolInfoTick()`** | `GET /api/{symbol}` or `GET /api/latest` | Cross-platform, JSON response, includes precomputed `mid` and `dayDiffPercent`. |
| **`CopyRates()`** | `GET /api/{symbol}/ohlc?interval=1h&limit=100` | No local buffer allocation, supports M1 through D1 intervals with real-time open bar flag (`isOpen`). |
| **`OnTick()` Event** | SignalR WebSocket: `https://biquote.io/hubs/tick` | Unmetered push streaming, handles auto-reconnect, zero terminal dependencies. |
| **Terminal Symbol Selection** | `GET /api/symbols?quotedWithinDays=7` | Real-time catalog filtering without manually querying broker MarketWatch. |

---

## 3. Feed Symbol Universe

The MT5 broker feed streams ~280 live instruments across asset classes:
1. **Forex**:
   - Majors: `EURUSD`, `GBPUSD`, `USDJPY`, `USDCHF`, `AUDUSD`, `USDCAD`, `NZDUSD`.
   - Minors & Exotics: `EURGBP`, `EURJPY`, `GBPJPY`, `EURCHF`, etc.
   - Emerging / TRY Crosses: `USDTRY`, `EURTRY`, `GBPTRY`.
2. **Precious Metals & Energy**:
   - `XAUUSD` (Spot Gold / USD)
   - `XAGUSD` (Spot Silver / USD)
   - `USOIL` (WTI Crude Oil)
3. **Cryptocurrency CFDs**:
   - `BTCUSD` (Bitcoin), `ETHUSD` (Ethereum), `SOLUSD` (Solana), `XRPUSD`, etc.
4. **Index & Equity CFDs**:
   - Indices: `US500` (S&P 500), `USTEC` (Nasdaq 100), `US30` (Dow Jones 30), `DE30` (DAX 40).
   - Major US Equities: Top liquid Nasdaq/NYSE names.

---

## 4. Tick Field Mapping

Each tick returned contains:
- `bid`: Best available broker selling price.
- `ask`: Best available broker buying price.
- `mid`: Standard midpoint reference price `(bid + ask) / 2`.
- `spread`: Difference between ask and bid.
- `high` / `low`: Current session extrema.
- `direction`: `"UP"`, `"DOWN"`, or `"FLAT"` vs prior tick.
- `dayDiffPercent`: Percentage delta from the session open price.
- `source`: Identifier string (e.g. `MetaTrader 5 (Broker 1)`).
