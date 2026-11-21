# Multi-Agent AI Quantitative Strategy Pipeline

TenX features an institutional-grade, 4-stage multi-agent AI quantitative reasoning pipeline. Rather than relying on a single generic LLM prompt that suffers from hallucinations and recency bias, TenX deploys specialized agents that debate, verify, and consolidate consensus trade recommendations.

---

## 1. Pipeline Architecture & Specialist Roles

```mermaid
graph TD
    subgraph Stage1 [Stage 1: Real-Market Ingestion]
        MarketData["RealMarketService (Live MT5 OHLC)"]
        StructureCalc["MarketStructureAnalysis (EMA 50/200, Swing Points, ATR, BBW)"]
    end

    subgraph Stage2 [Stage 2: Specialist Reasoning (Parallel)]
        SMC["SMC Structure Specialist (Break of Structure, Order Blocks, Liquidity Sweeps)"]
        Wyckoff["Wyckoff Phase Specialist (Accumulation/Distribution, Volume Climax, Springs)"]
        CustomSpecialist["Custom Specialist Agents (User Defined)"]
    end

    subgraph Stage3 [Stage 3: Adversarial Verification]
        Critic["Grounding Critic (Verifies Price Claims vs Real OHLC, Penalizes Hallucinations)"]
    end

    subgraph Stage4 [Stage 4: Institutional Consensus]
        Consolidator["Consolidator Officer (Final Trade Signal: Direction, Entry, SL, TP, Confidence)"]
    end

    MarketData --> StructureCalc
    StructureCalc --> SMC
    StructureCalc --> Wyckoff
    StructureCalc --> CustomSpecialist

    SMC --> Critic
    Wyckoff --> Critic
    CustomSpecialist --> Critic

    Critic --> Consolidator
```

---

## 2. Detailed Execution Stages

### Stage 1: Market Data Ingestion & Structure Analytics
Before dispatching any AI request, [RealMarketService.dart](file:///c:/Users/hp/Documents/Web-Projects/Alert-App/lib/services/realmarket_service.dart) fetches genuine broker candles and computes objective technical structure:
* **Trend Identification:** $EMA_{50}$ vs $EMA_{200}$ crossover and price position.
* **Swing Highs & Lows:** 5-candle fractals identifying verified support and resistance pivot levels.
* **Volatility & Consolidation:** 14-period ATR volatility and Bollinger Bandwidth ($BW \le 0.015$ marks compression/rangebound conditions).
* **Candle Context:** Recent OHLC history formatted into prompt-ready tabular data.

### Stage 2: Specialist Reasoning in Parallel
Specialist agents analyze the prepared market data simultaneously:
* **SMC Specialist:** Identifies Market Structure Breaks (MSB/BOS), Change of Character (CHoCH), Unmitigated Fair Value Gaps (FVG), and Institutional Order Blocks (OB).
* **Wyckoff Specialist:** Classifies trading ranges into Phases (A through E), evaluates Preliminary Supply/Support (PSY), Selling/Buying Climax (SC/BC), Automatic Rallies (AR), and Springs/UTADs.

### Stage 3: Adversarial Grounding Critic
To eliminate AI hallucinations, the **Grounding Critic** audits the specialist outputs:
1. Validates that referenced price levels actually exist within the high/low range of the supplied OHLC data.
2. Checks whether claim of "trend" matches the calculated $EMA_{50}/EMA_{200}$ relationship.
3. Challenges overly optimistic win probabilities and produces an adversarial critique.

### Stage 4: Consolidator Officer Synthesis
The **Consolidator Officer** evaluates the specialists' signals alongside the critic's audit to produce the final executable setup:
* `direction`: `BUY`, `SELL`, or `WAIT`
* `entryPrice`: Exact proposed limit/market entry
* `stopLoss`: Invalidation price level
* `takeProfit1` & `takeProfit2`: Realistic targets anchored to swing highs/lows
* `riskRewardRatio`: Mathematical ratio ($\ge 1.5$)
* `confidenceScore`: Integer between 1 and 100
* `reasoning`: Consolidated multi-perspective thesis

---

## 3. Strict JSON Extraction Protocol

LLMs frequently output conversational filler or preamble text around JSON blocks. TenX enforces resilient extraction via [ai_models.dart](file:///c:/Users/hp/Documents/Web-Projects/Alert-App/lib/models/ai_models.dart#L125-L165):

```dart
static Map<String, dynamic> extractJson(String rawText) {
  final clean = rawText.trim();

  // 1. Try markdown code fences ```json ... ```
  final codeBlockRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false);
  final match = codeBlockRegex.firstMatch(clean);
  if (match != null) {
    final blockContent = match.group(1)?.trim();
    if (blockContent != null && blockContent.isNotEmpty) {
      try {
        return jsonDecode(blockContent) as Map<String, dynamic>;
      } catch (_) {}
    }
  }

  // 2. Scan for raw outer curly braces {...}
  final firstBrace = clean.indexOf('{');
  final lastBrace = clean.lastIndexOf('}');
  if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
    final substring = clean.substring(firstBrace, lastBrace + 1);
    try {
      return jsonDecode(substring) as Map<String, dynamic>;
    } catch (_) {}
  }

  throw const FormatException('No valid JSON structure found in LLM response');
}
```

---

## 4. Custom Strategy Builder & Persistence

Traders can configure bespoke multi-agent setups via [strategies_screen.dart](file:///c:/Users/hp/Documents/Web-Projects/Alert-App/lib/screens/strategies_screen.dart):
* **Custom Prompts:** Add new specialist agents (e.g. Volume Profile Specialist, Fibonacci Harmonic Specialist, Macro Sentiment Specialist).
* **Timeframe Bundling:** Assign dedicated analysis timeframes (e.g. Multi-Timeframe Analysis across 15M + 4H).
* **Storage:** Strategies are serialized and persisted in SharedPreferences via `StrategyStorage.dart`. Completed analysis runs are logged with full agent transcripts into `HistoryStorage.dart`.
