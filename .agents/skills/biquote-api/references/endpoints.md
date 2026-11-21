# Biquote REST Endpoints Reference

Base URL: `https://biquote.io`
Authentication: **None (Free, No API Key, Open CORS)**
Rate Limit: **15,000 requests / minute per IP** (Fixed 1-minute window)

---

## 1. Tick Data Endpoints

### `GET /api/{symbol}`
Returns latest quote for a single instrument.
- **Path Parameter**:
  - `symbol` (`string`, required): e.g. `EURUSD`, `XAUUSD`, `BTCUSD`.
- **Query Parameter**:
  - `allowStale` (`bool`, optional, default `true`):
    - When `true`: If market is closed, returns HTTP 200 with last-known price, `marketState: "closed"`, and `stale: true`.
    - When `false`: Returns HTTP 404 as soon as quote is older than 5 minutes. (Recommended only for algorithmic trading execution).
- **Headers Returned**:
  - `X-Quote-State`: `"open"` or `"closed"`
  - `X-Quote-Age-Seconds`: Number of seconds elapsed since last tick
- **Status Codes**:
  - `200 OK`: Valid quote returned
  - `404 Not Found`: Unknown symbol or no data in >7 days

### `GET /api/latest`
Batch endpoint for multiple symbols. **Use this whenever displaying 2 or more instruments.**
- **Query Parameters**:
  - `symbols` (`string[]`, required): Repeat parameter for each symbol:
    - ✅ **Correct**: `?symbols=EURUSD&symbols=XAUUSD&symbols=BTCUSD`
    - ❌ **Wrong**: `?symbols=EURUSD,XAUUSD` (commas do NOT work)
  - `allowStale` (`bool`, optional, default `true`)
- **Response**:
  - JSON object keyed by symbol name: `{"EURUSD": { ... }, "XAUUSD": { ... }}`
  - If a symbol has never quoted, it is omitted from the object (check for key existence, not null).

### `GET /api/{symbol}/history`
Raw historical tick data.
- **Path Parameter**: `symbol` (`string`, required)
- **Query Parameter**: `count` (`int`, optional, default `100`, range `1-1000`)
- **Order**: Newest first.
- **Note**: Responses are large. Do not poll.

### `GET /api/active`
List of symbols currently receiving live ticks.
- **Returns**: Array of `ActiveSymbolInfo` (`name`, `description`, `type`, `exchange`, `source`).

---

## 2. Symbols & Catalogue

### `GET /api/symbols`
Catalog query with rich filtering.
- **Query Parameters**:
  - `quotedWithinDays` (`int 1-30`): **Recommended filter for UI pickers and dropdowns**. E.g. `?quotedWithinDays=7`.
  - `type` (`string`): `Forex`, `Stock`, `Crypto`, `Index`, `Commodity`
  - `source` (`string`): `MT5` or `MATRIKS`
  - `exchange` (`string`): e.g. `Forex`, `Crypto`
  - `activeOnly` (`bool`): Symbols broker marks active (default `false`)
  - `liveOnly` (`bool`): Symbols quoting *this second* (default `false`). Do not use for general UI as it empties on weekends.

### `GET /api/symbols/{name}`
Metadata for a single symbol (`name`, `digits`, `tickSize`, `contractSize`, `currency`, `hasData`, etc.).

### `GET /api/symbols/search`
Ranked search across symbol names and descriptions.
- **Query Parameters**:
  - `q` (`string`, required): Search keyword (e.g. `gold`, `EUR`, `Apple`)
  - `limit` (`int`, optional, default `25`, max `200`)
  - `liveOnly` (`bool`, optional, default `false`)

---

## 3. Market Statistics

### `GET /api/market/gainers`
Top gainers by percentage change.
- **Query Parameters**:
  - `limit` (`int`, optional, default `10`, range `1-100`)
  - `type` (`string`, optional): `Forex`, `Stock`, `Crypto`, etc.
  - `exchange` (`string`, optional)
  - `period` (`string`, optional, default `1D`): Note: calculation is based on session change since daily open.

### `GET /api/market/losers`
Top losers by percentage decline. Same parameters as `/api/market/gainers`.

### `GET /api/market/most-active`
Symbols with the largest intraday price range `(high - low) / mid`.
- **Query Parameters**: `limit` (default `10`), `type`, `exchange`.

### `GET /api/market/summary`
Snapshot totals: count of gaining, losing, and unchanged instruments per asset class.

---

## 4. News Feeds

### `GET /api/news/market`
Aggregated financial news (Google News + selected Hacker News).
- **Query Parameters**:
  - `symbol` (`string`, optional): Filter news by ticker (e.g. `AAPL`, `BTCUSD`)
  - `language` (`string`, default `en`): `en`, `tr`, `de`, etc.
  - `country` (`string`, default `US`): `US`, `TR`, `GB`, etc.
  - `maxResults` (`int`, default `10`, range `1-50`)

### `GET /api/news/hn`
Hacker News finance/tech stories.
- **Query Parameters**:
  - `q` (`string`, optional): Keyword search query (e.g. `bitcoin`)
  - `maxResults` (`int`, default `10`, range `1-50`)

---

## 5. Economic Calendar

### `GET /api/calendar`
Scheduled macroeconomic events and releases (54 countries).
- **Query Parameters**:
  - `from` (`ISO 8601`, default yesterday)
  - `to` (`ISO 8601`, default +7 days)
  - `countries` (`string`): Comma-separated ISO alpha-2 (`US,EU,TR,GB,JP`)
  - `importance` (`string`): `low`, `medium`, `high`
  - `type` (`string`): `event`, `indicator`, `holiday`
  - `limit` (`int`, default `200`, range `1-500`)
- **Returns**: Bare JSON array, ordered **oldest-first**.

### `GET /api/calendar/upcoming`
Next upcoming releases from the current time.
- **Query Parameters**: `limit` (default `20`, max `500`), `countries`, `importance`.

### `GET /api/calendar/countries`
List of supported country codes, names, and currencies in the calendar feed.

### `GET /api/calendar/{eventId}/history`
Historical release prints for a recurring event series (e.g. Nonfarm Payrolls).
- **Path Parameter**: `eventId` (e.g. `mql5:840`)
- **Query Parameter**: `limit` (default `24`, max `500`)

---

## 6. Candlestick (OHLC)

### `GET /api/{symbol}/ohlc`
Candlestick bar data.
- **Path Parameter**: `symbol` (`string`, required)
- **Query Parameters**:
  - `interval` (`string`, default `1h`): `1m`, `5m`, `15m`, `30m`, `1h`, `4h`, `1d`
  - `limit` (`int`, default `100`, range `1-1000`)
  - `from` (`ISO 8601`, optional)
  - `to` (`ISO 8601`, optional)
- **Envelope**: `{ "symbol": "...", "interval": "...", "bars": [...] }`
- **Bar Order**: **Newest first**. Must reverse before rendering in standard charts.
- **Open Bar**: If the current interval is forming, the first bar has `isOpen: true`.

---

## 7. System Health & Utilities

### `GET /health`
Returns system status JSON including feed and collector health.

### `GET /health/live` & `GET /health/ready`
Kubernetes liveness and readiness probes.

### `GET /s/{symbol}`
HTTP 301 redirect to the public web page for that instrument on `biquote.io`.
