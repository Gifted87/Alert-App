# Biquote Data Models Reference

This document provides complete schemas, fields, and critical handling rules for all data objects returned by the Biquote API (https://biquote.io/docs/).

---

## 1. Tick Object (`Tick` / `TickResponse`)

Represents real-time or last-known quote for an instrument.

```json
{
  "symbol": "EURUSD",
  "description": "Euro vs US Dollar",
  "bid": 1.08542,
  "ask": 1.08548,
  "mid": 1.08545,
  "spread": 0.00006,
  "last": 0.0,
  "volume": 0,
  "high": 1.08800,
  "low": 1.08530,
  "direction": "FLAT",
  "dayDiffPercent": -0.09,
  "timestamp": "2026-02-24T10:30:00Z",
  "time": "2026.02.24 10:30:00",
  "source": "MetaTrader 5 (Broker 1)",
  "marketState": "open",
  "stale": false,
  "quoteAgeSeconds": 0,
  "lastQuoteAt": "2026-02-24T10:30:00Z"
}
```

### Field Details:
| Field | Type | Description & Critical Rules |
|---|---|---|
| `symbol` | `string` | Ticker symbol (e.g. `EURUSD`, `XAUUSD`, `BTCUSD`). |
| `description` | `string` | Human-readable instrument name (e.g. `Euro vs US Dollar`). |
| `bid` | `number` | Current best bid price. |
| `ask` | `number` | Current best ask price. |
| `mid` | `number` | Midpoint price `(bid + ask) / 2`. **Always use `mid` as the reference price.** |
| `spread` | `number` | Spread `ask - bid`. |
| `last` | `number` | **Always 0.0**. This is broker CFD pricing without a centralized tape. Do not use. |
| `volume` | `number` | **Always 0**. No consolidated exchange volume. Do not use. |
| `high` | `number` | Highest price recorded during current trading session. |
| `low` | `number` | Lowest price recorded during current trading session. |
| `direction` | `string` | Direction vs prior tick: `"UP"`, `"DOWN"`, or `"FLAT"`. |
| `dayDiffPercent` | `number` | Percentage change since daily open. Meaningless when `stale` is true. |
| `timestamp` | `string` | ISO 8601 UTC timestamp (e.g. `2026-02-24T10:30:00Z`). **Always parse this field.** |
| `time` | `string` | MetaTrader 5 native string (e.g. `2026.02.24 10:30:00`). **Do NOT parse with `new Date()`.** |
| `source` | `string` | Data provider feed source (e.g. `MetaTrader 5 (Broker 1)`). |
| `marketState` | `string` | `"open"` or `"closed"`. Check this on every request! |
| `stale` | `boolean` | `true` if market is closed or quote is older than live stream. |
| `quoteAgeSeconds` | `integer` | Number of seconds elapsed since this price was received from broker. |
| `lastQuoteAt` | `string` | ISO 8601 UTC timestamp of the last quote arrival. |

---

## 2. Symbol Information (`SymbolInfo` & `ActiveSymbolInfo`)

### `SymbolInfo` (`GET /api/symbols`)
```json
{
  "name": "EURUSD",
  "description": "Euro vs US Dollar",
  "type": "Forex",
  "exchange": "Forex",
  "digits": 5,
  "tickSize": 0.00001,
  "tickValue": 1.0,
  "contractSize": 100000.0,
  "currency": "USD",
  "source": "MT5",
  "isActive": true,
  "hasData": true
}
```

### Critical Rules for Symbols:
- `type`: `Forex`, `Stock`, `Crypto`, `Index`, or `Commodity`.
- `source`: `MT5` or `MATRIKS`.
- `isActive`: Means "the broker lists this instrument". It is `true` for almost all ~1,700 items.
- `hasData`: Truly indicates whether market data has ever been received.
- **Picker filter**: Always pass `quotedWithinDays=7` to `GET /api/symbols`. Do not use `liveOnly=true` in UI pickers.

### `ActiveSymbolInfo` (`GET /api/active`)
```json
{
  "name": "EURUSD",
  "description": "Euro vs US Dollar",
  "type": "Forex",
  "exchange": "Forex",
  "source": "MT5"
}
```

---

## 3. Candlestick Object (`OhlcResponse` & `OhlcBar`)

### Envelope:
```json
{
  "symbol": "EURUSD",
  "interval": "1h",
  "bars": [ ... ]
}
```

### `OhlcBar` item:
```json
{
  "openTime": "2026-02-24T13:00:00Z",
  "open": 1.08521,
  "high": 1.08574,
  "low": 1.08498,
  "close": 1.08542,
  "volume": 0,
  "tickVolume": 340,
  "isOpen": true
}
```

### Critical Rules for OHLC:
- **Order**: Arrives **newest-first** (index 0 is newest). Must reverse for charting libraries.
- `isOpen`: `true` indicates the bar currently forming in real time; `false` indicates closed historical bar.
- `openTime`: Bar start time in ISO 8601 UTC.
- `tickVolume`: Number of ticks aggregated inside the bar interval (broker volume proxy).
- `volume`: Always 0 for Forex / CFDs.

---

## 4. Economic Calendar (`CalendarEvent` & `CalendarCountry`)

### `CalendarEvent`
```json
{
  "id": "mql5:900001",
  "eventId": "mql5:840",
  "time": "2026-08-07T12:30:00Z",
  "period": "2026-07-01T00:00:00Z",
  "countryCode": "US",
  "currency": "USD",
  "name": "Nonfarm Payrolls",
  "importance": "high",
  "type": "indicator",
  "sector": "jobs",
  "unit": "job",
  "multiplier": "thousands",
  "digits": 0,
  "actual": 152000,
  "forecast": 145000,
  "previous": 147000,
  "revisedPrevious": 149000,
  "revision": 1,
  "timeMode": "exact",
  "sourceUrl": "https://www.bls.gov/",
  "source": "mql5"
}
```

### Critical Calendar Rules:
- `actual`, `forecast`, `previous`, `revisedPrevious`: `null` means "not published yet" or "not applicable" (e.g. holidays). **Never coerce `null` to `0`!**
- Compare `actual` against `forecast` (not against `previous`).
- `multiplier`: E.g. `"thousands"`, `"millions"`. Used for display formatting (e.g., render `152000` as `152,000K`), do not multiply raw numbers again.
- `timeMode`: Can be `"exact"`, `"date"`, `"notime"`, or `"tentative"`. If not `"exact"`, do not display the time clock (it is a placeholder).
- `importance`: `"low"`, `"medium"`, `"high"`.
- `type`: `"indicator"`, `"event"`, or `"holiday"`.

### `CalendarCountry` (`GET /api/calendar/countries`)
```json
{
  "code": "US",
  "name": "United States",
  "currency": "USD"
}
```

---

## 5. Market Movers (`GainerLoser`, `MostActive`, `MarketOverview`)

### `GainerLoser`
```json
{
  "symbol": "XAUUSD",
  "description": "Gold vs US Dollar",
  "lastPrice": 4396.09,
  "changePercent": 4.25,
  "changeAmount": 179.20,
  "volume": 0
}
```

### `MostActive`
Ranked by intraday relative range: `(high - low) / mid` because raw volume is unavailable.
```json
{
  "symbol": "BTCUSD",
  "description": "Bitcoin vs US Dollar",
  "high": 68500.0,
  "low": 63200.0,
  "rangePercent": 8.12
}
```

### `MarketOverview` (`GET /api/market/summary`)
Snapshot of counts of gaining, losing, and unchanged instruments grouped across asset classes.

---

## 6. News Article (`NewsArticle`)

```json
{
  "title": "Fed Signals Interest Rate Stability",
  "description": "Summary of speech...",
  "url": "https://...",
  "publisher": "Reuters",
  "publishedDate": "2026-08-19T06:30:00Z",
  "imageUrl": null,
  "category": "market",
  "language": "en",
  "country": "US"
}
```
*Note: Interleaves market news with Hacker News items; distinguish via `publisher: "Hacker News"`.*
