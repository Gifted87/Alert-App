# TenX Global Settings Specification

This document defines the comprehensive architecture and functional specification for the **Global Settings Page** in the TenX Financial & Alert Terminal app.

---


## 1. Audio, Ringtone & Custom Sounds Engine (Critical Feature)

### 1.1 Global Default Ringtone (System & Bundled)
* **Interactive Tone Selector**: Displays the currently assigned system tone or bundled audio asset.
* **Dynamic System Sound Modal**: Tapping opens a bottom sheet populated dynamically by `AlarmService.getRingtones()`.
* **In-Line 3-Second Audio Preview**: Every tone in the list includes a dedicated `Play / Stop` button allowing immediate auditioning before selection.
* **Inheritance Rule**: Every new price level alert, technical indicator alert, multi-step chain, or economic calendar alert automatically inherits this global default ringtone *unless* explicitly overridden by the trader during individual alert creation.

### 1.2 Custom User Audio Upload / Import (New Addition)
* **Audio File Picker**: Direct integration with system file manager supporting `.mp3`, `.wav`, `.m4a`, and `.ogg` formats (up to 10 MB per file).
* **Sandboxed Local Storage**: Uploaded files are copied into internal protected app storage (`/data/user/0/.../app_flutter/custom_audio/`) so they persist across system updates and reboots.
* **"My Uploaded Tones" Library**:
  * Dedicated section in the ringtone selector displaying user-imported files with duration and file size.
  * In-line waveform/play-stop preview for each custom file.
  * Quick-action **"Set as Global Default"** button.
  * **Rename & Delete**: Option to rename or delete custom audio clips (auto-falls back to default alarm if an active alert's custom sound is deleted).
* **Cross-App Availability**: Any uploaded sound automatically appears as an option in all alert creation sheets (Price, Indicator, Pattern, Calendar).

### 1.3 Alarm Volume Slider & Force Max Volume
* **Master Volume Slider**: Dedicated 0% to 100% volume control for all trading alarms.
* **"Force Max Volume" Toggle**: Forces alarms to sound at 100% volume regardless of the current Android hardware media or ringer volume slider.

### 1.4 Volume Escalation (Gentle Wakeup) & Quiet Hours
* **Gradual Volume Ramp-Up**: Starts at 30% volume and smoothly ramps to 100% over 5 seconds, preventing ear-shattering jumps when headphones are connected.
* **Quiet Hours Schedule**:
  * **Start Time & End Time**: Configurable schedule (e.g. `23:00` to `07:00`).
  * **Quiet Hours Alarm Volume**: Dedicated volume slider during quiet hours (e.g., `20%` volume or `Vibrate Only`).
  * **Bypass Quiet Hours for Critical Alerts**: Optional toggle allowing High-Impact Economic News and Stop-Loss alerts to bypass quiet hours at full volume.

### 1.5 Vibration Mode
* **Configurable Vibration Patterns**:
  * `Continuous Alarm Pulse` (Standard rapid pulses)
  * `Heartbeat` (Short-Short-Long tactile rhythm)
  * `SOS Strobe` (Urgent triple-burst pattern)
  * `None` (Vibration disabled, audio only)

### 1.6 Alarm Duration & Auto-Silence
* **Timeout Behavior**:
  * `Ring continuously until dismissed` (Default — requires manual trader acknowledgment)
  * `Auto-silence after 30 seconds`
  * `Auto-silence after 60 seconds`

### 1.7 Text-to-Speech (TTS) Voice Announcements (New Addition)
* **Voice Speech Synthesizer**: Automatically synthesizes and speaks the alert details aloud before or alongside the alarm chime.
  * *Example*: *"EUR/USD crossed above 1.0850"* or *"High Impact News: US Core CPI in 5 minutes"*.
* **Speech Controls**: Adjustable speech rate (0.8x to 1.5x) and voice pitch.

### 1.8 Audio Ducking (New Addition)
* **Background Media Suppression**: Automatically ducks (lowers volume) or pauses external audio apps (Spotify, YouTube, Podcasts) when a trading alert fires, guaranteeing the alarm is heard.

### 1.9 Flashlight Strobe Alert (New Addition)
* **Camera LED Strobe**: Pulses the rear camera flashlight in sync with the alarm vibration. Invaluable in noisy trading rooms or when the smartphone is placed face-down on a desk.

### 1.10 Headphone Safety Volume Limiter (New Addition)
* **Hardware Detection**: Automatically detects when 3.5mm wired earphones or Bluetooth headsets are connected.
* **Safe Volume Ceiling**: Caps headset volume at 70% while keeping the external loudspeaker at 100%, protecting the trader's hearing during sudden volatility spikes.

---

## 2. Background Reliability & OS Permissions

### 2.1 Foreground Service Daemon Toggle
* **Live Service Status Indicator**: Real-time badge showing `Active (Green Pulse)` or `Suspended`.
* **Perpetual Foreground Execution**: Explains and manages the native Android Foreground Service that keeps WebSocket market feeds and scheduled calendar timers running 24/7 when the device is locked.

### 2.2 Unrestricted Battery Access (Battery Optimization Exemption)
* **One-Tap Exemption Request**: Calls `AlarmService.requestIgnoreBatteryOptimizations()`.
* **Live Status Pill**: `OPTIMAL (Whitelisted)` vs `ACTION NEEDED (Risk of Android deep sleep freeze)`.

### 2.3 Do Not Disturb (DND) Policy Override
* **Direct System Access**: Opens Android Notification Policy settings via `AlarmService.requestDndOverride()`.
* **Live Status Pill**: `GRANTED (Rings on Silent)` vs `MUTED ON SILENT`.

### 2.4 System Overlay & Lockscreen HUD Permission (`SYSTEM_ALERT_WINDOW` & `USE_FULL_SCREEN_INTENT`) (Critical Feature)
* **Core Problem Solved**: Currently, alarm dialogs only display when the app is actively open in the foreground. If the user is on the home screen, browsing the web, watching a video, or if the phone is locked, the alarm does not pop up visually.
* **Universal App Overlay (`SYSTEM_ALERT_WINDOW`)**:
  * Allows the app to draw an interactive trading alarm HUD directly over any running application (YouTube, WhatsApp, Chrome, games) without requiring the user to switch apps manually.
  * **One-Tap Permission Action**: Launches Android's *"Display over other apps"* system management screen via `Settings.ACTION_MANAGE_OVERLAY_PERMISSION`.
  * **Live Status Pill**: `GRANTED (Universal Overlay HUD Active)` vs `ACTION NEEDED (Restricted to in-app dialog only)`.
* **Full-Screen Lockscreen Overlay (`USE_FULL_SCREEN_INTENT`)**:
  * On Android 10–14+, enables high-priority full-screen incoming alerts over the keyguard/lock screen using `FLAG_SHOW_WHEN_LOCKED`, `FLAG_TURN_SCREEN_ON`, and `FLAG_KEEP_SCREEN_ON`.
  * Behaves exactly like an incoming phone call or native clock alarm.
  * **Live Status Pill**: `GRANTED (Lockscreen HUD Enabled)` vs `RESTRICTED`.
* **Overlay Alarm HUD Interface Components**:
  * **Floating Card**: High-contrast dark glassmorphic card with pulsing amber/green/red alert glow.
  * **Key Information**: Symbol badge (e.g., `XAU/USD`), Trigger Condition, Target Level, Live Tick Price, and Timestamp.
  * **Interactive Action Buttons**:
    * **`Snooze`**: Immediately applies the configured snooze duration (e.g., 5m) and stops the alarm.
    * **`Dismiss`**: Silences the alarm and archives the alert.
    * **`Open Chart`**: Unlocks/brings the app to the foreground and navigates directly to the symbol's live candlestick chart.

### 2.5 Background Polling Rate
* **Frequency Selector**:
  * `Ultra Fast (Every 2s)` — for aggressive scalping and tick-level alarms (higher battery consumption).
  * `Standard (Every 5s)` — optimal balance between accuracy and battery life (Default).
  * `Eco Battery Saver (Every 15s)` — lightweight monitoring for swing and daily traders.

### 2.6 Screen Wakeup on Alert
* **Display Activation**: Automatically wakes the display from sleep and turns on the lock screen with the full-screen trading HUD displaying the triggering price, symbol, and 1-tap Snooze / Dismiss buttons.

### 2.7 Persistent Status Bar Ticker
* **Ongoing Notification Ticker**: An optional pinned Android notification displaying the live real-time price and 24h change of your top watched asset (e.g. `XAU/USD: 2,724.80 ▲ +0.54%`).

### 2.8 Dead-Man / Connection Loss Warning
* **Connectivity Monitor**: If the device loses internet access for more than 3 minutes while active price alerts exist, the app sounds an alert warning that live market monitoring is currently offline.

### 2.9 Seamless Wi-Fi ↔ Cellular Network Failover
* **Automatic Re-Subscription**: Automatically resubscribes the Biquote live WebSocket feed and reconnects alerts when switching between Wi-Fi and mobile data networks.

### 2.10 Low Battery Alert Guard
* **Battery Warning**: Alerts the user when device battery falls below 15% so they are aware that aggressive background polling could trigger OS power-saving throttling.

---

## 3. AI Specialist & Inference Engine

### 3.1 Endpoint Configuration
* **Base URL**: Configurable URL field (e.g. `https://api.deepseek.com`, `https://api.openai.com`, or local Ollama `http://192.168.1.X:11434`).
* **API Key**: Obfuscated password field with toggleable show/hide eye icon.
* **Model Name**: Input field for LLM identifier (e.g. `deepseek-chat`, `deepseek-reasoner`, `gpt-4o`, `o1-mini`).

### 3.2 Inference Parameters
* **Temperature Slider**: Precision slider from `0.0` to `1.0` (Default `0.2` for rigorous analytical precision).
* **Max Tokens**: Token ceiling setting (`2048` or `4096` tokens).
* **Reasoning / Thinking Mode Toggle**: Enables chain-of-thought capture for reasoning models like DeepSeek-R1 and OpenAI o1/o3-mini.

### 3.3 Live Connection & Latency Tester
* **"Test Endpoint" Action**: Dispatches a 1-token test ping to the configured model.
* **Response Diagnostic**: Displays real-time round-trip latency in milliseconds (e.g. `Active · 240ms latency`) or detailed error diagnostics if the key/endpoint fails.

### 3.4 Concurrent vs Sequential Multi-Agent Execution (New Addition)
* **Execution Strategy**:
  * `Concurrent (Parallel)`: Runs Technical, Sentiment, Liquidity, and Risk specialists concurrently (3-5 seconds total deliberation).
  * `Sequential`: Executes specialists one by one to avoid rate-limit errors on strict free-tier API quotas.

### 3.5 Custom Persona Directive / Global Prompt Injection (New Addition)
* **Trader Directives Field**: An open text box appended to all specialist prompts.
  * *Example*: *"Focus strictly on London session liquidity sweeps"*, *"Prioritize conservative stop-losses"*, or *"Ignore news spikes under 15 pips"*.

### 3.6 Auto-Deliberation on Calendar Events (New Addition)
* **Scheduled AI Synthesis**: Automatically spins up an AI impact analysis 10 minutes prior to High-Impact (red folder) calendar releases and delivers a structured preparation briefing.

### 3.7 Token Usage & API Cost Counter (New Addition)
* **Usage Dashboard**: Displays total tokens consumed today and this month, calculated estimated API cost, breakdown of prompt vs completion tokens, and a 1-tap reset counter.

---

## 4. Market Data Providers (Biquote & RealMarket)

### 4.1 Biquote Live Stream Feed
* **Biquote API Key**: Editable API key field (pre-filled with default working key).
* **WebSocket Auto-Reconnect**: Toggle to automatically resubscribe SignalR streaming channels upon network disconnection.
* **Live Stream Status Indicator**: Real-time ping and socket connection health badge (`Connected · Ping: 34ms`).

### 4.2 RealMarket Historical Candles Feed
* **Base URL & Key**: Configuration for the 100-candle OHLCV data feed consumed by specialist models.
* **Feed Test Button**: Quick validation action requesting EURUSD 1H historical candles to verify data feed integrity.

### 4.3 Global Trading Timezone (New Addition)
* **Timezone Selector**: Controls timestamp rendering across charts, news feeds, and economic calendar:
  * `Local Device Time`
  * `UTC / GMT`
  * `New York (EST/EDT)` — US Market Hours
  * `London (GMT/BST)` — European Market Hours

### 4.4 Biquote Connection Quality & Network Fallback (New Addition)
* **Transport Fallback**: Option to automatically fall back from WebSocket streaming to 1-second REST polling if firewalls or weak mobile signals block socket traffic.

### 4.5 Spread & Slippage Display (New Addition)
* **Bid/Ask Spread Metric**: Toggle to display live broker spread in pips/points on the chart header and alert cards.

### 4.6 Offline Candle Cache Retention (New Addition)
* **Local Storage Cache**: Choose how many historical bars are cached locally per symbol (`500`, `1,000`, or `2,000` bars) for instantaneous offline chart rendering without network spinners.

### 4.7 Trading Session Open Alerts (Multi-Select) (New Addition)
* **Purpose**: Automatically notifies and alerts the trader when global financial market trading sessions open, allowing them to prepare for liquidity surges and session open volatility.
* **Multi-Select Session Chips / Checkboxes**:
  * `Sydney Open` (`21:00 UTC`) — AUD, NZD pairs
  * `Tokyo / Asian Open` (`00:00 UTC`) — JPY pairs, Nikkei
  * `London / European Open` (`07:00 UTC / 08:00 UTC DST`) — GBP, EUR pairs, DAX
  * `New York / US Open` (`12:00 UTC / 13:00 UTC DST`) — USD pairs, Gold (XAU), US Indices
  * `London / NY Overlap` (`12:00 – 16:00 UTC`) — Peak daily global liquidity window
* **Alert Timing Selector**:
  * `At Session Open (Exact)`
  * `5 Minutes Before Open`
  * `15 Minutes Before Open`
* **Alert Execution & Feedback**:
  * Triggers the configured session bell / ringtone.
  * Optional TTS Voice Announcement (e.g., *"London Trading Session is now open. Focus: GBP, EUR"*).
  * System overlay / lockscreen HUD displays active session summary and top correlated currency pairs.

---

## 5. Alert Trigger & Snooze Rules

### 5.1 Default Snooze Duration
* **Time Increments**: Configurable selector: `3 mins`, `5 mins (Default)`, `10 mins`, or `15 mins`.

### 5.2 Alert Expiration / Time-To-Live (TTL) (New Addition)
* **Stale Alert Cleanup**: Auto-deactivates unhit price alerts after `24 Hours`, `3 Days`, `1 Week`, or `Never (Default)`.
---

## 6. Chart & Terminal UX Defaults

### 6.1 Default Launch Screen
* **Initial Route**: Choose which screen opens on app start:
  * `Market Watch (Chart Screen)`
  * `Economic Calendar`
  * `AI Deliberation`

### 6.2 Default Chart Timeframe
* **Starting Bar Period**: Set default chart timeframe upon opening any symbol: `1m`, `5m`, `15m (Default)`, `1H`, `4H`, `1D`.

### 6.3 Chart Style Defaults
* **Candle Type**: `Solid Japanese Candlesticks`, `Hollow Candles`, or `Line Chart`.
* **Show Sub-second Price Countdown Timer**: Toggle countdown timer displaying remaining time until the current bar closes.
* **Vibrate on Price Line Drag**: Haptic tactile clicks when dragging target alert lines across the chart canvas.

### 6.4 Magnetic Snapping / Smart Crosshair (New Addition)
* **Snap to Levels**: When drawing or dragging price lines, automatically snaps to candle High, Low, Open, Close, or major round psychological numbers (`.00`, `.50`).

### 6.5 Active Market Session Background Shading (New Addition)
* **Session Highlights**: Renders subtle translucent vertical bands on the chart background for Tokyo, London, and New York market hours.

### 6.6 Colorblind-Friendly Chart Modes (New Addition)
* **Color Palettes**:
  * `Standard (Emerald Green / Crimson Red)`
  * `Deuteranopia / High-Contrast (Cyan Blue / Amber Orange)`
  * `Monochrome OLED (Pure White / Dim Gray)`

---

## 7. Data Storage, Backup, Security & Diagnostics

### 7.1 Backup & Migration
* **Export All Data to JSON**: Generates a single encrypted/formatted JSON file containing all custom AI specialists, deliberation history, and alert definitions.
* **Import Backup**: Restores configurations from a saved backup file with validation.

### 7.2 History Management
* **Clear Fired Alert History**: Purges triggered alert logs without affecting active pending alerts.
* **Clear Cached Market Candles**: Clears local disk cache to force clean downloads from the market data feed.

### 7.3 Diagnostics Terminal
* **Device Telemetry**: Shows device model, Android SDK level, background service PID, and memory footprint.
* **"Copy Diagnostic Log" Button**: Copies system diagnostics to clipboard for technical support.

### 7.4 Reset to Factory Defaults
* **Factory Reset**: Safeguarded button with dual-confirmation dialog to reset all preferences, storage, and models back to original factory defaults.

### 7.5 Biometric / PIN App Lock (New Addition)
* **Security Shield**: Optional Fingerprint, Face ID, or 4-digit PIN authentication required to open the app or resume from background, protecting proprietary trading strategies and API keys.

### 7.6 Trading Journal Export to CSV (New Addition)
* **Performance Journaling**: Exports past AI signals, market prices, and specialist deliberation votes to a structured CSV spreadsheet for backtesting analysis.

### 7.7 Network & Endpoint Diagnostics Suite (New Addition)
* **1-Click System Ping**: Runs a concurrent ping test across all 4 critical endpoints:
  1. Biquote SignalR WebSocket
  2. RealMarket historical candle REST API
  3. Configured LLM inference endpoint
  4. Android Foreground Service daemon heartbeat

### 7.8 One-Tap Diagnostic Report Sharing (New Addition)
* **Sanitized Logs**: Generates an anonymized diagnostic report (with API keys redacted) that can be copied or shared to troubleshoot connectivity or alarm issues.

---
