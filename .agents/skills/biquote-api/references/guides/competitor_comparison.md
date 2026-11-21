# Biquote vs. Competitor Market Data APIs

Sources:
- Alpha Vantage Alternative: https://biquote.io/guides/alpha-vantage-alternative.html
- TwelveData Alternative: https://biquote.io/guides/twelvedata-alternative.html
- Finnhub Alternative: https://biquote.io/guides/finnhub-alternative.html

## 1. Feature Comparison Matrix

| Feature | Biquote (Free) | Alpha Vantage (Free) | TwelveData (Free) | Finnhub (Free) |
|---|---|---|---|---|
| **API Key / Registration** | **None (100% anonymous)** | Required | Required | Required |
| **Rate Limit** | **15,000 req/min per IP** | 25 req/day (or 5/min) | 8 credits/min, 800/day | 60 calls/min |
| **WebSocket Streaming** | **Free & Unmetered** (SignalR) | Paid tier only | Paid tier only | Free (stocks & crypto trades only) |
| **Forex & Gold Quotes** | Real-time OTC broker feed (~280 live) | Limited / delayed | Limited within credits | Behind paid plan |
| **Forex / Gold OHLC Candles** | 1m to 1d (up to 1,000 bars) | Intraday limited | Within credits | Paid tier |
| **Economic Calendar** | 54 countries (JSON, free) | None | None | Paid tier |
| **Embeddable Widgets** | 12 widgets (1.4 KB loader) | None | None | None |
| **US Equity Fundamentals & Financials** | ❌ None (CFD quotes only) | ✅ Yes (Major strength) | ✅ Yes | ✅ Yes (Major strength) |
| **Decades of Historical Stock Bars** | ❌ None (~1 year rolling) | ✅ Yes | ✅ Yes | ✅ Yes |

---

## 2. In-Depth Provider Breakdown

### Biquote vs. Alpha Vantage
- **Pain point with Alpha Vantage**: The free tier cap of 25 requests/day terminates development projects quickly when polling or rendering multi-symbol dashboards.
- **When Biquote is better**: Real-time Forex, Spot Gold/Silver, Crypto, and Index CFD streaming at high request volumes without authentication.
- **When Alpha Vantage is better**: Long-term quantitative backtesting of US stocks over 20+ years, balance sheets, income statements, and SEC filing data.

### Biquote vs. TwelveData
- **Pain point with TwelveData**: Complex credit metering where each symbol, interval, or indicator consumes API credits, with strict 8 credit/minute throttling and WebSockets locked behind paid tiers.
- **When Biquote is better**: Dashboards polling 20+ symbols or bots streaming live ticks 24/7 without worrying about running out of daily credits.
- **When TwelveData is better**: Global physical equity exchanges (e.g., Tokyo Stock Exchange, London Stock Exchange) and corporate dividend adjustments.

### Biquote vs. Finnhub
- **Pain point with Finnhub**: Finnhub offers a great free tier for US stocks, but accessing Forex pairs or Gold candlestick charts requires upgrading to paid tiers.
- **When Biquote is better**: Free access to Forex, Metals, and a 54-country macroeconomic calendar with actual/forecast values.
- **When Finnhub is better**: Company earnings calendars, executive transcripts, insider transactions, and social media sentiment analysis for US equities.
