# Technical Indicators & Candlestick Pattern Engine

TenX includes a high-performance quantitative calculation engine implemented with strict 1:1 parity between Flutter Dart ([indicator_calculator.dart](file:///c:/Users/hp/Documents/Web-Projects/Alert-App/lib/services/indicator_calculator.dart)) and Android Kotlin ([AlertForegroundService.kt](file:///c:/Users/hp/Documents/Web-Projects/Alert-App/android/app/src/main/kotlin/com/example/alert_app/AlertForegroundService.kt)).

---

## 1. Technical Indicators Mathematical Specification

### A. Relative Strength Index (RSI)
RSI measures momentum by comparing the magnitude of recent gains to recent losses over period $N$ (default $N=14$).

1. **Price Changes:**
   $$\Delta P_t = P_t - P_{t-1}, \quad U_t = \max(\Delta P_t, 0), \quad D_t = \max(-\Delta P_t, 0)$$
2. **Smoothing:**
   * **Wilder's RMA (Default):**
     $$\overline{U}_t = \frac{\overline{U}_{t-1} \times (N - 1) + U_t}{N}, \quad \overline{D}_t = \frac{\overline{D}_{t-1} \times (N - 1) + D_t}{N}$$
   * **EMA:**
     $$\alpha = \frac{2}{N + 1}, \quad \overline{U}_t = (U_t \times \alpha) + (\overline{U}_{t-1} \times (1 - \alpha))$$
3. **Index Calculation:**
   $$RS = \frac{\overline{U}_t}{\overline{D}_t}, \quad RSI = 100 - \left( \frac{100}{1 + RS} \right)$$
* **Conditions Supported:** `crossesAboveLevel`, `crossesBelowLevel`, `crossesAboveOversold` (<30), `crossesBelowOverbought` (>70), `crossesAboveCenterline` (50), `crossesBelowCenterline` (50), `rsiTurningUp` (momentum hook), `rsiTurningDown`, `crossesAboveSignalMa`, `crossesBelowSignalMa`.

---

### B. Moving Average Convergence Divergence (MACD)
Standard MACD parameters: Fast $= 12$, Slow $= 26$, Signal $= 9$.

1. **MACD Line:**
   $$MACD_t = EMA_{Fast}(P) - EMA_{Slow}(P)$$
2. **Signal Line:**
   $$Signal_t = EMA_{Signal}(MACD)$$
3. **Histogram:**
   $$Hist_t = MACD_t - Signal_t$$
* **Conditions Supported:** `bullishSignalCross` ($MACD > Signal$), `bearishSignalCross` ($MACD < Signal$), `zeroLineCrossAbove` ($MACD > 0$), `zeroLineCrossBelow` ($MACD < 0$), `histogramFlipPositive`, `histogramFlipNegative`, `histogramTurningUp`, `histogramTurningDown`.

---

### C. Moving Averages & MA Crossover
Supports EMA, SMA, and WMA across user-defined periods (e.g. 50/200 Golden Cross).

* **Simple Moving Average (SMA):**
  $$SMA_t = \frac{1}{N} \sum_{i=0}^{N-1} P_{t-i}$$
* **Exponential Moving Average (EMA):**
  $$\alpha = \frac{2}{N+1}, \quad EMA_t = (P_t \times \alpha) + (EMA_{t-1} \times (1 - \alpha))$$
* **Weighted Moving Average (WMA):**
  $$WMA_t = \frac{\sum_{i=0}^{N-1} (N - i) P_{t-i}}{\frac{N(N+1)}{2}}$$
* **Conditions Supported:** `goldenCross` ($Fast > Slow$), `deathCross` ($Fast < Slow$), `priceCrossesAboveFast`, `priceCrossesBelowFast`, `priceCrossesAboveSlow`, `priceCrossesBelowSlow`, `priceAboveBoth`, `priceBelowBoth`, `priceBetweenMAs`.

---

### D. Bollinger Bands
Parameters: Period $N = 20$, Standard Deviation Multiplier $K = 2.0$.

1. **Middle Band:** $Middle_t = SMA_N(P)$
2. **Standard Deviation:**
   $$\sigma_t = \sqrt{\frac{1}{N} \sum_{i=0}^{N-1} (P_{t-i} - Middle_t)^2}$$
3. **Upper & Lower Bands:**
   $$Upper_t = Middle_t + (K \times \sigma_t), \quad Lower_t = Middle_t - (K \times \sigma_t)$$
4. **Bandwidth & %B:**
   $$Bandwidth_t = \frac{Upper_t - Lower_t}{Middle_t}, \quad \%B_t = \frac{P_t - Lower_t}{Upper_t - Lower_t}$$
* **Conditions Supported:** `priceCrossesAboveUpper`, `priceCrossesBelowUpper`, `priceCrossesBelowLower`, `priceCrossesAboveLower`, `middleBandCrossAbove`, `middleBandCrossBelow`, `squeeze` ($BW \le 0.015$), `squeezeBreakout` ($BW_{prev} \le Threshold \land BW_{curr} > Threshold$), `percentBCrossesAbove80`, `percentBCrossesBelow20`.

---

### E. Stochastic Oscillator
Parameters: $\%K = 14$, $\%K\text{ Slowing} = 3$, $\%D = 3$.

1. **Raw Stochastic:**
   $$Fast\%K = \frac{Close_t - \min(Low_{t-13..t})}{\max(High_{t-13..t}) - \min(Low_{t-13..t})} \times 100$$
2. **Full $\%K$:** $SMA_{Slowing}(Fast\%K)$
3. **Signal $\%D$:** $SMA_D(\%K)$
* **Conditions Supported:** `bullishCross` ($\%K > \%D$), `bearishCross` ($\%K < \%D$), `bullishOversoldCross` ($\%K > \%D \land \%K \le 20$), `bearishOverboughtCross` ($\%K < \%D \land \%K \ge 80$), `kCrossesAbove50`, `kCrossesBelow50`.

---

### F. Supertrend
Parameters: Period $N = 10$, Multiplier $M = 3.0$, ATR Smoothing: Wilder RMA.

1. **True Range (TR):**
   $$TR_t = \max(High_t - Low_t, |High_t - Close_{t-1}|, |Low_t - Close_{t-1}|)$$
2. **Average True Range (ATR):** $ATR_t = RMA_N(TR)$
3. **Basic Bands:**
   $$BasicUpper_t = \frac{High_t + Low_t}{2} + (M \times ATR_t), \quad BasicLower_t = \frac{High_t + Low_t}{2} - (M \times ATR_t)$$
4. **Final Bands & Ratcheting Logic:**
   $$FinalUpper_t = (BasicUpper_t < FinalUpper_{t-1} \lor Close_{t-1} > FinalUpper_{t-1}) \ ?\ BasicUpper_t : FinalUpper_{t-1}$$
   $$FinalLower_t = (BasicLower_t > FinalLower_{t-1} \lor Close_{t-1} < FinalLower_{t-1}) \ ?\ BasicLower_t : FinalLower_{t-1}$$
5. **Trend Flip:**
   $$Trend_t = \begin{cases} +1 & \text{if } Close_t > FinalUpper_{t-1} \\ -1 & \text{if } Close_t < FinalLower_{t-1} \\ Trend_{t-1} & \text{otherwise} \end{cases}$$
* **Conditions Supported:** `bullishFlip` ($Trend_{prev} = -1 \land Trend_{curr} = 1$), `bearishFlip` ($Trend_{prev} = 1 \land Trend_{curr} = -1$), `priceCrossesAboveTrail`, `priceCrossesBelowTrail`, `priceBouncesOffTrail`, `priceDistanceGreaterThan`.

---

## 2. Candlestick Pattern Recognition Engine

Both Flutter ([candlestick_detector.dart](file:///c:/Users/hp/Documents/Web-Projects/Alert-App/lib/services/candlestick_detector.dart)) and Android Kotlin enforce closed-candle evaluation:
* Bar $0$ ($c0$): Latest completed, closed candle.
* Bar $1$ ($c1$): 1 candle prior.
* Bar $2$ ($c2$): 2 candles prior.

| Pattern | Type | Geometric Detection Formula |
| :--- | :--- | :--- |
| **Bullish Engulfing** | Bullish Reversal | $c1.isBearish \land c0.isBullish \land c0.body > c1.body \land c0.open \le c1.close \land c0.close \ge c1.open$ |
| **Bearish Engulfing** | Bearish Reversal | $c1.isBullish \land c0.isBearish \land c0.body > c1.body \land c0.open \ge c1.close \land c0.close \le c1.open$ |
| **Hammer** | Bullish Reversal | $c0.body \le 0.35 \times Range \land c0.lowerShadow \ge 2 \times Body \land c0.upperShadow \le 0.15 \times Range \land (c1.isBearish \lor c0.low < c1.low)$ |
| **Shooting Star** | Bearish Reversal | $c0.body \le 0.35 \times Range \land c0.upperShadow \ge 2 \times Body \land c0.lowerShadow \le 0.15 \times Range \land (c1.isBullish \lor c0.high > c1.high)$ |
| **Morning Star** | Bullish Reversal | $c2.isBearish \land c2.body \ge 0.45 \times Range \land c1.body \le 0.35 \times c2.body \land c0.isBullish \land c0.close \ge (c2.close + 0.5 \times c2.body)$ |
| **Evening Star** | Bearish Reversal | $c2.isBullish \land c2.body \ge 0.45 \times Range \land c1.body \le 0.35 \times c2.body \land c0.isBearish \land c0.close \le (c2.open + 0.5 \times c2.body)$ |
| **Standard Doji** | Neutral / Indecision | $c0.body \le 0.08 \times Range$ |
| **Dragonfly Doji** | Bullish Reversal | $c0.body \le 0.08 \times Range \land c0.upperShadow \le 0.12 \times Range \land c0.lowerShadow \ge 0.65 \times Range$ |
| **Gravestone Doji** | Bearish Reversal | $c0.body \le 0.08 \times Range \land c0.lowerShadow \le 0.12 \times Range \land c0.upperShadow \ge 0.65 \times Range$ |
| **Piercing Line** | Bullish Reversal | $c1.isBearish \land c0.isBullish \land c0.open \le c1.low \land c0.close \ge (c1.close + 0.5 \times c1.body) \land c0.close \le c1.open$ |
| **Dark Cloud Cover** | Bearish Reversal | $c1.isBullish \land c0.isBearish \land c0.open \ge c1.high \land c0.close \le (c1.open + 0.5 \times c1.body) \land c0.close \ge c1.open$ |
| **Three White Soldiers** | Bullish Continuation | 3 consecutive bullish bars with higher closes, opens within prior body, small upper shadows ($\le 0.25 \times Range$). |
| **Three Black Crows** | Bearish Continuation | 3 consecutive bearish bars with lower closes, opens within prior body, small lower shadows ($\le 0.25 \times Range$). |
| **Bullish Harami** | Bullish Reversal | $c1.isBearish \land c0.isBullish \land c0.open \ge c1.close \land c0.close \le c1.open \land c0.body < c1.body \times 0.7$ |
| **Bearish Harami** | Bearish Reversal | $c1.isBullish \land c0.isBearish \land c0.open \le c1.close \land c0.close \ge c1.open \land c0.body < c1.body \times 0.7$ |
| **Tweezer Bottom** | Bullish Reversal | $c1.isBearish \land c0.isBullish \land |c1.low - c0.low| \le (c1.low \times 0.00015) \land c0.lowerShadow \ge 0.3 \times Range$ |
| **Tweezer Top** | Bearish Reversal | $c1.isBullish \land c0.isBearish \land |c1.high - c0.high| \le (c1.high \times 0.00015) \land c0.upperShadow \ge 0.3 \times Range$ |
| **Marubozu** | Momentum Continuation | $c0.body \ge 0.88 \times Range$ (full candle body with minimal or zero wicks). |
