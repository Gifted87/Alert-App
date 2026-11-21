# Testing, Verification & Deployment Guide

This document details the automated testing methodology, static analysis gates, Android production APK compilation process, cryptographic checksum verification, and the local distribution web downloader server.

---

## 1. Automated Test Suite

TenX maintains automated test suites covering all mathematical indicators, boundary crossing rules, multi-step chain logic, and LLM extraction protocols.

### Test Execution Commands
```bash
# Run all project tests
flutter test

# Run individual test files
flutter test test/engine_fixes_test.dart
flutter test test/ai_pipeline_test.dart
flutter test test/widget_test.dart
```

### Coverage Breakdown

#### A. Alert Engine & Mathematical Fixes (`test/engine_fixes_test.dart`)
1. **Candlestick Pattern Timing:** Confirms open forming bar (`isOpen: true`) is ignored and pattern matching evaluates confirmed closed bars (`isOpen: false`).
2. **Step Timeout & Auto-Reset:** Confirms that if a stage exceeds `timeoutMinutes`, `config.isTimedOut(now)` returns `true` and `config.reset()` restores Stage 1.
3. **Stage Remaining Duration:** Confirms `config.timeRemaining(now)` returns exact remaining minutes and seconds, returning `Duration.zero` once expired.
4. **False-Positive Prevention:** Confirms an alert created when price is already above target ($P_{initial} = 1.1550, Target = 1.1500$) does **not** trigger on the first tick; requires price to dip below $1.1500$ and cross upward.
5. **Hysteresis Cooldown & Re-Crossing:** Verifies alerts in cooldown suppress triggers, track $P_{prev}$ accurately on every tick, and only re-fire when cooldown expires and a fresh boundary transition occurs.
6. **Multi-Currency Price Isolation:** Verifies `createMultiSymbolAlerts` assigns genuine market prices per symbol (e.g. EURUSD: 1.0850, USDJPY: 155.30, XAUUSD: 2650.00) and clones independent stage trees.
7. **JSON Persistence Serialization:** Validates bi-directional serialization of nested multi-step stages, node operators (`OR`/`AND`), negations, and timestamps.

#### B. Multi-Agent AI & Indicator Logic (`test/ai_pipeline_test.dart`)
1. **TradingStrategy Serialization:** Verifies default agent prompts and timeframe arrays.
2. **AgentSignal JSON Extraction:** Validates regex parsing of Markdown code blocks (` ```json ... ``` `) and raw JSON strings.
3. **RealMarket Symbol & Timeframe Normalization:** Tests canonical code mapping (e.g. `GOLD` $\rightarrow$ `XAUUSD`, `15m` $\rightarrow$ `M15`).
4. **RSI Bounded Calculations:** Tests Wilder RMA smoothing and confirms RSI outputs remain bounded between 0 and 100.
5. **Pattern Detector Geometry:** Tests Bullish and Bearish Engulfing detection logic.

#### C. App Smoke Test (`test/widget_test.dart`)
1. **App Launch Smoke Test:** Verifies `TenXApp` mounts successfully without widget tree exceptions.

---

## 2. Static Code Analysis

Before any release build, code is analyzed using the Flutter Lint standard:
```bash
flutter analyze
```
* **Acceptance Criteria:** `No issues found! (ran in X.Xs)`. Zero errors and zero warnings.

---

## 3. Production Release APK Compilation

The production Android binary is compiled with R8 code shrinking and bytecode tree-shaking:

```bash
flutter build apk --release
```

### Build Specifications
* **Output Path:** `build/app/outputs/flutter-apk/app-release.apk`
* **Target OS:** Android 8.0+ (API Level 26+)
* **Architecture:** Universal Release (arm64-v8a, armeabi-v7a, x86_64)
* **Binary Size:** ~55.5 MB (`58,166,488 bytes`)

---

## 4. Cryptographic Checksum Verification

To ensure binary integrity between build environments and user devices, every build is fingerprinted via SHA-256:

### Computing Checksum (PowerShell)
```powershell
Get-FileHash "build\app\outputs\flutter-apk\app-release.apk" -Algorithm SHA256
```

### Verified Production Hash
```
Algorithm       Hash
---------       ----
SHA256          C8BA5F2307FCF96A1E95FC318B210DDCC3F697E4E0D7B32453D87936955AD06F
```

---

## 5. Web Downloader Distribution Server

TenX includes a standalone, responsive distribution portal located in `tenx-web-downloader/`:

### Structure
* `index.html`: Modern dark-mode web portal showcasing live features, screenshots, specifications, direct download button, and SHA-256 integrity badge.
* `app.js`: Dynamic QR code generator using client local IP, clipboard copying for URLs and checksums.
* `style.css`: Glassmorphism aesthetics with smooth animations.
* `downloads/TenX-v1.0-release.apk`: Production binary target.

### Serving Locally
```powershell
# Run from repository root
cd tenx-web-downloader
python -m http.server 8088
```
* **Local Web URL:** `http://localhost:8088`
* **Network Download URL:** `http://<YOUR_LAN_IP>:8088/downloads/TenX-v1.0-release.apk`
* **Verification:** Mobile devices on the same Wi-Fi network can scan the on-screen QR code to download and install the APK directly.
