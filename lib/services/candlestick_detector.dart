import 'dart:math';

import '../models/market_models.dart';

class CandlestickDetector {
  /// Evaluates whether the given candlestick pattern is formed on the latest completed candles.
  /// [candles] must be provided in chronological order (oldest to newest).
  /// If [requireClosedCandle] is true (default), any open, currently-forming candle is ignored,
  /// evaluating strictly completed and confirmed closed candles.
  static bool matches(
    CandlestickPattern pattern,
    List<BiquoteCandle> candles, {
    bool requireClosedCandle = true,
  }) {
    if (candles.isEmpty) return false;

    // Filter out active in-progress candle if needed, or use the latest closed candles
    final bool lastIsOpen = candles.last.isOpen;
    final int offset = (requireClosedCandle && lastIsOpen) ? 1 : 0;

    final int c0Index = candles.length - 1 - offset;
    final int c1Index = candles.length - 2 - offset;
    final int c2Index = candles.length - 3 - offset;

    if (c0Index < 0 || c1Index < 0) return false;

    final c0 = candles[c0Index]; // Latest completed candle
    final c1 = candles[c1Index]; // 1 candle ago
    final c2 = c2Index >= 0 ? candles[c2Index] : null; // 2 candles ago

    switch (pattern) {
      case CandlestickPattern.bullishEngulfing:
        return _isBullishEngulfing(c1, c0);
      case CandlestickPattern.bearishEngulfing:
        return _isBearishEngulfing(c1, c0);
      case CandlestickPattern.hammer:
        return _isHammer(c0, c1);
      case CandlestickPattern.hangingMan:
        return _isHangingMan(c0, c1);
      case CandlestickPattern.shootingStar:
        return _isShootingStar(c0, c1);
      case CandlestickPattern.invertedHammer:
        return _isInvertedHammer(c0, c1);
      case CandlestickPattern.morningStar:
        return c2 != null && _isMorningStar(c2, c1, c0);
      case CandlestickPattern.eveningStar:
        return c2 != null && _isEveningStar(c2, c1, c0);
      case CandlestickPattern.doji:
        return _isDoji(c0);
      case CandlestickPattern.dragonflyDoji:
        return _isDragonflyDoji(c0);
      case CandlestickPattern.gravestoneDoji:
        return _isGravestoneDoji(c0);
      case CandlestickPattern.piercingLine:
        return _isPiercingLine(c1, c0);
      case CandlestickPattern.darkCloudCover:
        return _isDarkCloudCover(c1, c0);
      case CandlestickPattern.threeWhiteSoldiers:
        return c2 != null && _isThreeWhiteSoldiers(c2, c1, c0);
      case CandlestickPattern.threeBlackCrows:
        return c2 != null && _isThreeBlackCrows(c2, c1, c0);
      case CandlestickPattern.bullishHarami:
        return _isBullishHarami(c1, c0);
      case CandlestickPattern.bearishHarami:
        return _isBearishHarami(c1, c0);
      case CandlestickPattern.tweezerBottom:
        return _isTweezerBottom(c1, c0);
      case CandlestickPattern.tweezerTop:
        return _isTweezerTop(c1, c0);
      case CandlestickPattern.marubozu:
        return _isMarubozu(c0);
    }
  }

  // --- Candle Metric Helpers ---
  static double _body(BiquoteCandle c) => (c.close - c.open).abs();
  static double _range(BiquoteCandle c) => max(0.000001, c.high - c.low);
  static double _upperShadow(BiquoteCandle c) => c.high - max(c.open, c.close);
  static double _lowerShadow(BiquoteCandle c) => min(c.open, c.close) - c.low;

  // 1. Engulfing
  static bool _isBullishEngulfing(BiquoteCandle prev, BiquoteCandle curr) {
    if (prev.close >= prev.open) return false; // prev must be red
    if (curr.close <= curr.open) return false; // curr must be green
    final prevBody = _body(prev);
    final currBody = _body(curr);
    return currBody > prevBody &&
        curr.open <= prev.close &&
        curr.close >= prev.open;
  }

  static bool _isBearishEngulfing(BiquoteCandle prev, BiquoteCandle curr) {
    if (prev.close <= prev.open) return false; // prev must be green
    if (curr.close >= curr.open) return false; // curr must be red
    final prevBody = _body(prev);
    final currBody = _body(curr);
    return currBody > prevBody &&
        curr.open >= prev.close &&
        curr.close <= prev.open;
  }

  // 2. Hammer & Hanging Man
  static bool _isHammer(BiquoteCandle curr, BiquoteCandle prev) {
    final body = _body(curr);
    final range = _range(curr);
    final lower = _lowerShadow(curr);
    final upper = _upperShadow(curr);

    final isPinBar =
        body <= 0.35 * range && lower >= 2.0 * body && upper <= 0.15 * range;
    final isDowntrend = prev.close < prev.open || curr.low < prev.low;
    return isPinBar && isDowntrend;
  }

  static bool _isHangingMan(BiquoteCandle curr, BiquoteCandle prev) {
    final body = _body(curr);
    final range = _range(curr);
    final lower = _lowerShadow(curr);
    final upper = _upperShadow(curr);

    final isPinBar =
        body <= 0.35 * range && lower >= 2.0 * body && upper <= 0.15 * range;
    final isUptrend = prev.close > prev.open || curr.high > prev.high;
    return isPinBar && isUptrend;
  }

  // 3. Shooting Star & Inverted Hammer
  static bool _isShootingStar(BiquoteCandle curr, BiquoteCandle prev) {
    final body = _body(curr);
    final range = _range(curr);
    final lower = _lowerShadow(curr);
    final upper = _upperShadow(curr);

    final isInvertedPin =
        body <= 0.35 * range && upper >= 2.0 * body && lower <= 0.15 * range;
    final isUptrend = prev.close > prev.open || curr.high > prev.high;
    return isInvertedPin && isUptrend;
  }

  static bool _isInvertedHammer(BiquoteCandle curr, BiquoteCandle prev) {
    final body = _body(curr);
    final range = _range(curr);
    final lower = _lowerShadow(curr);
    final upper = _upperShadow(curr);

    final isInvertedPin =
        body <= 0.35 * range && upper >= 2.0 * body && lower <= 0.15 * range;
    final isDowntrend = prev.close < prev.open || curr.low < prev.low;
    return isInvertedPin && isDowntrend;
  }

  // 4. Morning Star & Evening Star
  static bool _isMorningStar(
    BiquoteCandle c1,
    BiquoteCandle c2,
    BiquoteCandle c3,
  ) {
    // c1: Strong red
    if (c1.close >= c1.open || _body(c1) < 0.45 * _range(c1)) return false;
    // c2: Small star
    if (_body(c2) > 0.35 * _body(c1)) return false;
    // c3: Strong green closing above 50% midpoint of c1
    if (c3.close <= c3.open) return false;
    final midpoint = c1.close + (_body(c1) * 0.5);
    return c3.close >= midpoint;
  }

  static bool _isEveningStar(
    BiquoteCandle c1,
    BiquoteCandle c2,
    BiquoteCandle c3,
  ) {
    // c1: Strong green
    if (c1.close <= c1.open || _body(c1) < 0.45 * _range(c1)) return false;
    // c2: Small star
    if (_body(c2) > 0.35 * _body(c1)) return false;
    // c3: Strong red closing below 50% midpoint of c1
    if (c3.close >= c3.open) return false;
    final midpoint = c1.open + (_body(c1) * 0.5);
    return c3.close <= midpoint;
  }

  // 5. Doji variations
  static bool _isDoji(BiquoteCandle c) {
    return _body(c) <= 0.08 * _range(c);
  }

  static bool _isDragonflyDoji(BiquoteCandle c) {
    final range = _range(c);
    return _body(c) <= 0.08 * range &&
        _upperShadow(c) <= 0.12 * range &&
        _lowerShadow(c) >= 0.65 * range;
  }

  static bool _isGravestoneDoji(BiquoteCandle c) {
    final range = _range(c);
    return _body(c) <= 0.08 * range &&
        _lowerShadow(c) <= 0.12 * range &&
        _upperShadow(c) >= 0.65 * range;
  }

  // 6. Piercing Line & Dark Cloud Cover
  static bool _isPiercingLine(BiquoteCandle prev, BiquoteCandle curr) {
    if (prev.close >= prev.open) return false; // prev must be red
    if (curr.close <= curr.open) return false; // curr must be green
    final prevMidpoint = prev.close + (_body(prev) * 0.5);
    return curr.open <= prev.low &&
        curr.close >= prevMidpoint &&
        curr.close <= prev.open;
  }

  static bool _isDarkCloudCover(BiquoteCandle prev, BiquoteCandle curr) {
    if (prev.close <= prev.open) return false; // prev must be green
    if (curr.close >= curr.open) return false; // curr must be red
    final prevMidpoint = prev.open + (_body(prev) * 0.5);
    return curr.open >= prev.high &&
        curr.close <= prevMidpoint &&
        curr.close >= prev.open;
  }

  // 7. Three White Soldiers & Three Black Crows
  static bool _isThreeWhiteSoldiers(
    BiquoteCandle c1,
    BiquoteCandle c2,
    BiquoteCandle c3,
  ) {
    return (c1.close > c1.open) &&
        (c2.close > c2.open) &&
        (c3.close > c3.open) &&
        (c2.close > c1.close) &&
        (c3.close > c2.close) &&
        (c2.open > c1.open && c2.open < c1.close) &&
        (c3.open > c2.open && c3.open < c2.close) &&
        (_upperShadow(c3) <= 0.25 * _range(c3));
  }

  static bool _isThreeBlackCrows(
    BiquoteCandle c1,
    BiquoteCandle c2,
    BiquoteCandle c3,
  ) {
    return (c1.close < c1.open) &&
        (c2.close < c2.open) &&
        (c3.close < c3.open) &&
        (c2.close < c1.close) &&
        (c3.close < c2.close) &&
        (c2.open < c1.open && c2.open > c1.close) &&
        (c3.open < c2.open && c3.open > c2.close) &&
        (_lowerShadow(c3) <= 0.25 * _range(c3));
  }

  // 8. Harami
  static bool _isBullishHarami(BiquoteCandle prev, BiquoteCandle curr) {
    if (prev.close >= prev.open) return false; // prev must be red
    if (curr.close <= curr.open) return false; // curr must be green
    return curr.open >= prev.close &&
        curr.close <= prev.open &&
        _body(curr) < _body(prev) * 0.7;
  }

  static bool _isBearishHarami(BiquoteCandle prev, BiquoteCandle curr) {
    if (prev.close <= prev.open) return false; // prev must be green
    if (curr.close >= curr.open) return false; // curr must be red
    return curr.open <= prev.close &&
        curr.close >= prev.open &&
        _body(curr) < _body(prev) * 0.7;
  }

  // 9. Tweezers
  static bool _isTweezerBottom(BiquoteCandle prev, BiquoteCandle curr) {
    if (prev.close >= prev.open) return false; // prev red
    if (curr.close <= curr.open) return false; // curr green
    final diff = (prev.low - curr.low).abs();
    return diff <= (prev.low * 0.00015) &&
        _lowerShadow(curr) >= 0.3 * _range(curr);
  }

  static bool _isTweezerTop(BiquoteCandle prev, BiquoteCandle curr) {
    if (prev.close <= prev.open) return false; // prev green
    if (curr.close >= curr.open) return false; // curr red
    final diff = (prev.high - curr.high).abs();
    return diff <= (prev.high * 0.00015) &&
        _upperShadow(curr) >= 0.3 * _range(curr);
  }

  // 10. Marubozu
  static bool _isMarubozu(BiquoteCandle c) {
    final body = _body(c);
    final range = _range(c);
    return body >= 0.88 * range;
  }
}
