/**
 * Biquote SignalR Real-Time Client (Node.js / Browser)
 * Run: npm install @microsoft/signalr
 */

import * as signalR from '@microsoft/signalr';

const SYMBOLS = ['EURUSD', 'XAUUSD', 'BTCUSD'];

async function main() {
  console.log('1. Hydrating initial prices via batch REST call...');
  // Anti-pattern averted: repeat symbols parameter, never use commas
  const qs = SYMBOLS.map(s => `symbols=${s}`).join('&');
  const res = await fetch(`https://biquote.io/api/latest?${qs}`);
  const seed = await res.json();

  for (const [symbol, tick] of Object.entries(seed)) {
    const status = tick.marketState === 'closed'
      ? `[CLOSED - Last: ${tick.mid}]`
      : `[LIVE: ${tick.mid} (${tick.dayDiffPercent.toFixed(2)}%)]`;
    console.log(`Initial: ${symbol.padEnd(8)} ${status}`);
  }

  console.log('\n2. Connecting to unmetered SignalR hub (/hubs/tick)...');
  const connection = new signalR.HubConnectionBuilder()
    .withUrl('https://biquote.io/hubs/tick')
    .withAutomaticReconnect([0, 2000, 5000, 10000, 30000])
    .build();

  // Handle incoming live tick
  // Handler block avoids returning a value to prevent SignalR invocation warnings
  connection.on('ReceiveTick', (tick) => {
    console.log(`⚡ TICK: ${tick.symbol} -> Mid: ${tick.mid} (Bid: ${tick.bid}, Ask: ${tick.ask})`);
  });

  // Handle subscription state validation
  connection.on('ReceiveSubscriptionState', (states) => {
    for (const s of states) {
      if (s.state === 'unknown') {
        console.warn(`⚠️ Warning: Symbol ${s.symbol} is unknown or not carried on this feed.`);
      } else {
        console.log(`✓ Subscription confirmed: ${s.symbol} (state: ${s.state}, seeded: ${s.seeded})`);
      }
    }
  });

  // Re-subscribe when reconnecting
  connection.onreconnected(async () => {
    console.log('🔄 Reconnected! Resubscribing symbols...');
    await connection.invoke('Subscribe', SYMBOLS);
  });

  await connection.start();
  console.log('Connected! Subscribing to symbols...');
  await connection.invoke('Subscribe', SYMBOLS);
}

main().catch(console.error);
