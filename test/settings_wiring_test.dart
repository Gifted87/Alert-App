import 'package:flutter_test/flutter_test.dart';
import 'package:alert_app/models/market_models.dart';
import 'package:alert_app/services/alarm_service.dart';
import 'package:alert_app/services/realmarket_service.dart';
import 'package:alert_app/services/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SettingsProvider().resetToDefaults();
  });

  group('SettingsProvider & Global Settings Specification Tests', () {
    test('Defaults match specification baseline', () {
      final sp = SettingsProvider();
      expect(sp.soundTitle, 'Siren');
      expect(sp.alarmVolume, 0.85);
      expect(sp.forceMaxVolume, false);
      expect(sp.volumeEscalation, true);
      expect(sp.quietHoursEnabled, true);
      expect(sp.quietHours, '23:00 – 07:00');
      expect(sp.quietHoursVolume, 0.25);
      expect(sp.vibrationMode, 'Continuous');
      expect(sp.alarmAutoSilence, 'Never');
      expect(sp.ttsEnabled, false);
      expect(sp.audioDucking, true);
      expect(sp.flashlightStrobe, false);
      expect(sp.headphoneSafety, true);

      expect(sp.perpetualServiceActive, true);
      expect(sp.pollingRate, 'Standard (5s)');
      expect(sp.pollingDuration, const Duration(seconds: 5));
      expect(sp.screenWakeup, true);
      expect(sp.statusBarTicker, true);
      expect(sp.deadManWarning, true);
      expect(sp.autoNetworkFailover, true);
      expect(sp.lowBatteryGuard, true);

      expect(sp.llmTemperature, 0.20);
      expect(sp.llmMaxTokens, 2048);
      expect(sp.aiExecutionStrategy, 'Parallel');

      expect(sp.biquoteAutoReconnect, true);
      expect(sp.tradingTimezone, 'UTC / GMT');
      expect(sp.transportFallback, true);
      expect(sp.showSpreadDisplay, true);
      expect(sp.candleRetentionCount, 1000);

      expect(sp.defaultSnoozeMinutes, 5);
      expect(sp.alertTtl, 'Never');
      expect(sp.ttlDuration, isNull);

      expect(sp.defaultLaunchScreen, 'Market Watch');
      expect(sp.defaultChartTimeframe, '15m');
      expect(sp.chartCandleType, 'Japanese Candles');
      expect(sp.showCandleCountdown, true);
      expect(sp.vibrateOnDrag, true);
      expect(sp.magneticSnapping, true);
      expect(sp.sessionShading, true);
      expect(sp.colorblindChartMode, 'Standard');
      expect(sp.biometricAppLock, false);
    });

    test('Quiet Hours window calculation and effective volume resolution', () async {
      final sp = SettingsProvider();
      await sp.setQuietHoursEnabled(true);
      await sp.setQuietHours('23:00 – 07:00');
      await sp.setQuietHoursVolume(0.25);
      await sp.setAlarmVolume(0.85);

      // 02:30 AM (Inside quiet hours)
      final nightTime = DateTime(2026, 10, 19, 2, 30);
      expect(sp.isNowInQuietHours(nightTime), true);
      expect(sp.resolveEffectiveVolume(time: nightTime), 0.25);

      // Bypass critical
      await sp.setQuietHoursBypassCritical(true);
      expect(sp.resolveEffectiveVolume(isCritical: true, time: nightTime), 0.85);

      // Force max volume overrides quiet hours
      await sp.setForceMaxVolume(true);
      expect(sp.resolveEffectiveVolume(time: nightTime), 1.0);
      await sp.setForceMaxVolume(false);

      // 14:00 PM (Outside quiet hours)
      final dayTime = DateTime(2026, 10, 19, 14, 0);
      expect(sp.isNowInQuietHours(dayTime), false);
      expect(sp.resolveEffectiveVolume(time: dayTime), 0.85);
    });

    test('Adaptive Polling Rate and Candle Retention conversions', () async {
      final sp = SettingsProvider();

      await sp.setPollingRate('Ultra Fast (2s)');
      expect(sp.pollingDuration, const Duration(seconds: 2));

      await sp.setPollingRate('Eco Battery Saver (15s)');
      expect(sp.pollingDuration, const Duration(seconds: 15));

      await sp.setPollingRate('Standard (5s)');
      expect(sp.pollingDuration, const Duration(seconds: 5));

      await sp.setOfflineCandleRetention('500 bars');
      expect(sp.candleRetentionCount, 500);

      await sp.setOfflineCandleRetention('2,000 bars');
      expect(sp.candleRetentionCount, 2000);
    });

    test('Auto-Silence seconds resolution', () async {
      final sp = SettingsProvider();

      await sp.setAlarmAutoSilence('Never');
      expect(sp.autoSilenceSeconds, 0);

      await sp.setAlarmAutoSilence('30 seconds');
      expect(sp.autoSilenceSeconds, 30);

      await sp.setAlarmAutoSilence('60 seconds');
      expect(sp.autoSilenceSeconds, 60);
    });

    test('Stale Alert TTL resolution', () async {
      final sp = SettingsProvider();

      await sp.setAlertTtl('Never');
      expect(sp.ttlDuration, isNull);

      await sp.setAlertTtl('24 Hours');
      expect(sp.ttlDuration, const Duration(hours: 24));

      await sp.setAlertTtl('3 Days');
      expect(sp.ttlDuration, const Duration(days: 3));

      await sp.setAlertTtl('1 Week');
      expect(sp.ttlDuration, const Duration(days: 7));
    });

    test('JSON Export and Import restores full settings state', () async {
      final sp = SettingsProvider();

      await sp.setSound('Custom Gong', 'custom_gong_uri');
      await sp.setAlarmVolume(0.95);
      await sp.setTradingTimezone('Tokyo (JST)');
      await sp.setChartCandleType('Line Chart');
      await sp.setBiometricAppLock(true);
      await sp.setAiExecutionStrategy('Sequential');

      final exportedMap = sp.exportSettingsToJson();
      expect(exportedMap['soundTitle'], 'Custom Gong');
      expect(exportedMap['soundUri'], 'custom_gong_uri');
      expect(exportedMap['alarmVolume'], 0.95);
      expect(exportedMap['tradingTimezone'], 'Tokyo (JST)');
      expect(exportedMap['chartCandleType'], 'Line Chart');
      expect(exportedMap['biometricAppLock'], true);
      expect(exportedMap['aiExecutionStrategy'], 'Sequential');

      // Reset to factory defaults
      await sp.resetToDefaults();
      expect(sp.soundTitle, 'Siren');
      expect(sp.tradingTimezone, 'UTC / GMT');
      expect(sp.chartCandleType, 'Japanese Candles');
      expect(sp.biometricAppLock, false);

      // Import back
      await sp.importSettingsFromJson(exportedMap);
      expect(sp.soundTitle, 'Custom Gong');
      expect(sp.soundUri, 'custom_gong_uri');
      expect(sp.alarmVolume, 0.95);
      expect(sp.tradingTimezone, 'Tokyo (JST)');
      expect(sp.chartCandleType, 'Line Chart');
      expect(sp.biometricAppLock, true);
      expect(sp.aiExecutionStrategy, 'Sequential');
    });

    test('Listeners are notified when settings change', () async {
      final sp = SettingsProvider();
      int notifyCount = 0;
      sp.addListener(() {
        notifyCount++;
      });

      await sp.setAlarmVolume(0.50);
      await sp.setFlashlightStrobe(true);
      await sp.setDefaultChartTimeframe('1H');

      expect(notifyCount, 3);
      expect(sp.alarmVolume, 0.50);
      expect(sp.flashlightStrobe, true);
      expect(sp.defaultChartTimeframe, '1H');
    });

    test('BiquoteCandle serialization round-trip', () {
      final candle = BiquoteCandle(
        openTime: DateTime.utc(2026, 10, 19, 3, 0),
        open: 1.0850,
        high: 1.0865,
        low: 1.0842,
        close: 1.0860,
        tickVolume: 42,
        isOpen: false,
      );

      final json = candle.toJson();
      expect(json['open'], 1.0850);
      expect(json['close'], 1.0860);
      expect(json['tickVolume'], 42);

      final restored = BiquoteCandle.fromJson(json);
      expect(restored.open, candle.open);
      expect(restored.close, candle.close);
      expect(restored.high, candle.high);
      expect(restored.low, candle.low);
      expect(restored.tickVolume, candle.tickVolume);
    });

    test('RealMarketService offline cache retention and purge', () async {
      await RealMarketService.clearCandleCache();
      expect(RealMarketService.getCachedCandleCount(), 0);

      // Verify clearCandleCache resets count cleanly
      final purged = await RealMarketService.clearCandleCache();
      expect(purged, 0);
    });

    test('AlarmService getSystemTelemetry returns non-empty dynamic telemetry', () async {
      final alarmService = AlarmService();
      final telemetry = await alarmService.getSystemTelemetry();

      expect(telemetry.containsKey('os'), true);
      expect(telemetry.containsKey('abi'), true);
      expect(telemetry.containsKey('model'), true);
      expect(telemetry.containsKey('pid'), true);
      expect(telemetry.containsKey('daemonRunning'), true);
      expect(telemetry.containsKey('dndGranted'), true);
      expect(telemetry.containsKey('batteryIgnored'), true);
      expect(telemetry.containsKey('overlayGranted'), true);
      expect(telemetry.containsKey('memoryUsedMb'), true);
    });
  });
}
