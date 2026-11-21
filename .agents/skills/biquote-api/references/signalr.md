# Biquote SignalR / WebSocket Streaming Reference

Hub URL: `https://biquote.io/hubs/tick`
Protocol: **ASP.NET Core SignalR** (WebSocket transport with SSE / long-polling fallback)
Rate Limit: **Unmetered (Zero rate limit impact)**

---

## 1. Why Use SignalR Instead of REST Polling

1. **Unmetered**: SignalR connections and pushed ticks do not count against the 15,000 req/min IP rate limit.
2. **Sub-second Latency**: Ticks are pushed immediately as received from the broker feed.
3. **Bandwidth Efficient**: Avoids redundant HTTP header overhead and server load.
4. **Instant Seeding**: Upon subscribing to a symbol, the hub immediately emits one seed tick representing the latest known price—even when the market is closed.

---

## 2. Client-to-Server Methods

Use `connection.invoke(methodName, ...args)`:

| Method | Arguments | Return Type | Description |
|---|---|---|---|
| `Subscribe` | `symbols: string[]` | `void` | Subscribes connection to tick updates for one or more symbols. E.g. `['EURUSD', 'XAUUSD']`. |
| `Unsubscribe` | `symbols: string[]` | `void` | Stops receiving updates for the specified symbols. |
| `GetLatestTick` | `symbol: string` | `Tick` | Requests immediate quote object for a specific symbol. |
| `GetSubscriptions` | *(none)* | `string[]` | Returns array of symbol names currently subscribed on this connection. |

---

## 3. Server-to-Client Events

Register handlers using `connection.on(eventName, handler)`:

### `ReceiveTick`
Fired whenever a new market tick arrives for any subscribed symbol.
- **Payload**: `Tick` object (see [models.md](./models.md))
- **Handler Note**: Always use a block handler that does not return a value. In JS: `(tick) => { ... }`. Do NOT use an arrow function with implicit return `tick => someArray.push(tick)`, as SignalR will treat the returned value as an invocation response and log a warning.

### `ReceiveSubscriptionState`
Fired immediately after `Subscribe` is invoked.
- **Payload**: Array of state objects:
  ```json
  [
    {
      "symbol": "EURUSD",
      "state": "open",
      "quoteAgeSeconds": 0,
      "seeded": true
    },
    {
      "symbol": "INVALID",
      "state": "unknown",
      "quoteAgeSeconds": 0,
      "seeded": false
    }
  ]
  ```
- **State Values**:
  - `"open"`: Market is open and live ticks are flowing.
  - `"closed"`: Market is closed (e.g. weekend Forex). A seed quote was provided.
  - `"unknown"`: Symbol is not carried by the feed or is misspelled. Use this to warn users or clear invalid tickers.

---

## 4. Connection Lifecycle & Best Practices

1. **Automatic Reconnect**:
   Always enable automatic reconnect with exponential backoff.
   ```javascript
   const connection = new signalR.HubConnectionBuilder()
     .withUrl('https://biquote.io/hubs/tick')
     .withAutomaticReconnect([0, 2000, 5000, 10000, 30000])
     .build();
   ```

2. **Resubscribing on Reconnect**:
   SignalR clears server-side group registrations when a connection drops and reconnects with a new connection ID. Listen to `onreconnected` to re-issue `Subscribe`:
   ```javascript
   connection.onreconnected(async (connectionId) => {
     console.log('Reconnected:', connectionId);
     if (activeSymbols.length > 0) {
       await connection.invoke('Subscribe', activeSymbols);
     }
   });
   ```

3. **Hybrid Hydration Pattern**:
   - Step 1: Make a single batch REST call `GET /api/latest?symbols=A&symbols=B` to render UI immediately on page load.
   - Step 2: Establish the SignalR connection and invoke `Subscribe`.
   - Step 3: Stream live ticks seamlessly.
