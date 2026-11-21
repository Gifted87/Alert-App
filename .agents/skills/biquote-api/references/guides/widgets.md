# Biquote Embeddable Market Widgets Guide

Source: https://biquote.io/guides/tradingview-widget-alternative.html
Widget Playground: https://widgets.biquote.io/#widgets

## 1. Overview

Biquote provides 12 plug-and-play financial widgets that serve as lightweight alternatives to TradingView embeds.
- **Ultra-lightweight**: The base loader script is **1.4 KB gzipped** (`loader.js`).
- **Lazy Loading**: Only downloads the JavaScript for the specific widgets placed on the page.
- **Real-Time Streaming**: Powered by live SignalR WebSockets from MetaTrader 5 feeds.
- **Zero API Key Needed**: A public key is automatically handled per publisher origin.
- **Customizable**: Light, dark, and auto OS-tracking themes (`data-theme="auto"`).
- **Optional Attribution**: Brand watermark can be disabled via `data-attribution="false"`.
- **Strict CSP Support**: Can be embedded directly as standard iframes via `https://widgets.biquote.io/embed/{widgetName}`.

---

## 2. Quick Embed Script Tag

Place this single script tag once in your HTML `<head>` or before `</body>`:

```html
<script src="https://widgets.biquote.io/v1/loader.js" async></script>
```

---

## 3. The 12 Available Widgets

| Widget Name (`data-biquote-widget`) | Description | Example Embed Tag |
|---|---|---|
| **`ticker`** | Horizontal scrolling price tape for any ticker list | `<div data-biquote-widget="ticker" data-symbols="EURUSD,XAUUSD,BTCUSD,USDJPY"></div>` |
| **`pricecard`** | Single-symbol in-depth card with 24-hour sparkline | `<div data-biquote-widget="pricecard" data-symbol="EURUSD"></div>` |
| **`chart`** | Interactive price chart with range selectors and comparison | `<div data-biquote-widget="chart" data-symbol="XAUUSD" data-range="1D"></div>` |
| **`watchlist`** | Multi-symbol tabular watch list (reader customizable) | `<div data-biquote-widget="watchlist" data-symbols="EURUSD,GBPUSD,USDJPY,XAUUSD"></div>` |
| **`movers`** | Top gainers, losers, and most active instruments (tabbed) | `<div data-biquote-widget="movers" data-type="Forex"></div>` |
| **`overview`** | Multi-asset dashboard (Forex, Crypto, Indices, Metals) | `<div data-biquote-widget="overview"></div>` |
| **`heatmap`** | Grid visualizing market movement by relative color intensity | `<div data-biquote-widget="heatmap"></div>` |
| **`breadth`** | Ratio and counts of advancing vs. declining instruments | `<div data-biquote-widget="breadth"></div>` |
| **`crossrates`** | Real-time currency exchange rate matrix table | `<div data-biquote-widget="crossrates" data-currencies="USD,EUR,GBP,JPY,CHF"></div>` |
| **`converter`** | Live currency converter calculator with cross-rates | `<div data-biquote-widget="converter" data-from="USD" data-to="EUR"></div>` |
| **`news`** | Streaming financial headlines feed | `<div data-biquote-widget="news" data-symbol="AAPL" data-max="5"></div>` |
| **`calendar`** | Macroeconomic release calendar with actual/forecast values | `<div data-biquote-widget="calendar" data-countries="US,EU,TR" data-importance="medium"></div>` |

---

## 4. Common Attributes & Customization Options

| Attribute | Values | Description |
|---|---|---|
| `data-biquote-widget` | `ticker`, `chart`, `calendar`, etc. | Specifies which widget to instantiate. |
| `data-theme` | `"auto"`, `"dark"`, `"light"` | Default `"auto"` (follows user's OS dark mode setting). |
| `data-attribution` | `"true"`, `"false"` | Default `"true"`. Set `"false"` to hide the small "data by biquote.io" credit. |
| `data-symbols` | Comma-separated tickers (e.g. `EURUSD,XAUUSD`) | Tickers to load in the widget. |
| `data-countries` | Comma-separated ISO alpha-2 codes (e.g. `US,EU,TR,GB`) | Calendar filter. |
| `data-importance` | `"low"`, `"medium"`, `"high"` | Calendar filter. |
| `data-range` | `"1D"`, `"1W"`, `"1M"`, `"1Y"` | Default view range for chart widgets. |

---

## 5. Strict Content Security Policy (CSP) Iframe Fallback

For websites prohibiting third-party JavaScript execution via strict CSP headers:

```html
<iframe
  src="https://widgets.biquote.io/embed/ticker?symbols=EURUSD,XAUUSD,BTCUSD&theme=dark"
  width="100%"
  height="48"
  frameborder="0"
  scrolling="no">
</iframe>
```
