# Architecture, Infrastructure & Operational Economics of Biquote

Source: https://biquote.io/guides/what-free-costs.html

## 1. Real-World Telemetry & Traffic Profile

In a public case study published by the Biquote team analyzing a full 24-hour traffic sample:
- **Total Requests**: 13,792,750 requests / day (~160 requests per second sustained).
- **Total Daily Egress**: 13.24 GB.
- **Unique Client IPs**: 2,468 unique IP addresses.

### Extreme Traffic Concentration
Traffic follows an extreme power-law distribution:
- **Top 1 IP address**: Accounted for **9,188,005 requests (67% of all traffic)**.
- **Top 3 IP addresses**: Accounted for **78%** of all traffic.
- **Top 12 IP addresses**: Accounted for **95%** of all traffic.
- The remaining ~2,450 unique developers split just 5% of total volume.

### Root Cause Analysis of Heavy Consumers
The top consumer was running two parallel jobs:
1. `GET /api/latest?symbols=...` (20 at a time) — 93,198 requests.
2. `GET /api/{symbol}/ohlc?interval=1m&limit=1` — **1,132,840 requests** (looping through every catalogue symbol once per minute).
*Lesson*: The single-symbol loop was written first, worked reliably, and was never refactored because the free API never throttled or billed the client.

---

## 2. The WebSocket Under-Utilization Paradox

| Protocol / Endpoint | Daily Requests / Connections | Relative Frequency |
|---|---|---|
| `GET /api/{symbol}/ohlc` | 1,234,795 requests | Common |
| `GET /api/{symbol}` | 465,157 requests | Frequent |
| `GET /api/latest` | 150,890 requests | Moderate |
| **`/hubs/tick` (SignalR WebSocket)** | **744 upgrades** | **< 0.01%** |

Despite WebSockets being cheaper for both client and server, faster, and completely unmetered, 99.9% of integrations defaulted to REST polling loops. This prompted Biquote to redesign its documentation to prioritize SignalR snippets over REST.

---

## 3. Server Footprint & Cost Breakdown

Despite serving nearly 14 million requests daily, the entire Biquote ingestion and distribution platform operates with a remarkably minimal footprint:

```text
Component             RAM Usage       CPU Usage      Data Stored
-----------------------------------------------------------------
biquote container     141.5 MiB       ~1/3 of a core Feed fan-out, API engine
redis                 116.9 MB        Minimal        7,130 active keys
```

### The Real Cost Drivers:
1. **Network Egress**: ~400 GB/month (~$36 on standard metered cloud hosting).
2. **Disk Logging**: ~13 GB of Nginx access logs generated every day.
3. **Compute**: Negligible (< $10/month equivalent).

---

## 4. Rate Limiting Philosophy

- **15,000 requests/minute per IP**: Selected specifically to be high enough that legitimate developers will never collide with it.
- The top client averaging 6,400 requests/minute stayed well within the threshold.
- The rate limiter functions as a **Denial of Service (DoS) safety brake**, not as a monetization funnel or fair-share governor.
- Developers are strongly encouraged to use `/hubs/tick` or `/api/latest` to minimize unnecessary egress and latency.
