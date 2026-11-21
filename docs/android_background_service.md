# Android Perpetual Background Service Daemon

The native Android architecture ensures the TenX Terminal functions as a mission-critical financial monitor. It runs a perpetual foreground service daemon that survives app swipes, screen locks, Doze mode battery optimizations, and device restarts.

---

## 1. Native Service Architecture Overview

```mermaid
graph TD
    subgraph OS_Triggers [Android System Triggers]
        Boot[BOOT_COMPLETED / QUICKBOOT]
        WatchdogTimer[AlarmWatchdog Repeating Timer]
        FlutterStart[Flutter MethodChannel Start Service]
    end

    subgraph CoreService [AlertForegroundService (Kotlin)]
        WakeLock[Partial WakeLock (CPU Active)]
        PersistentNotif[Ongoing Notification ID 1001]
        PollThread[Background Polling Thread (1-3s Loop)]
        OHLCCache[In-Memory OHLC Cache (10s TTL)]
        EvalEngine[Stateful Crossing & Indicator Evaluator]
    end

    subgraph AlarmDelivery [Alarm & Alert Delivery]
        AudioPlayer[AlarmPlayer (Audio USAGE_ALARM / DND Bypass)]
        FullScreenIntent[Full-Screen Alarm Intent (Wake Screen)]
        AlarmNotif[Heads-Up Notification (ID: 2000+)]
    end

    Boot --> CoreService
    WatchdogTimer --> CoreService
    FlutterStart --> CoreService

    CoreService --> WakeLock
    CoreService --> PersistentNotif
    CoreService --> PollThread
    PollThread --> OHLCCache
    PollThread --> EvalEngine

    EvalEngine -->|Condition Triggered| AudioPlayer
    EvalEngine -->|Condition Triggered| FullScreenIntent
    EvalEngine -->|Condition Triggered| AlarmNotif
```

---

## 2. Notification Channel Architecture & ID Segregation

Android Oreo (API 26+) requires explicit notification channels. To prevent heads-up alarm popups from colliding with or dismissing the perpetual service, TenX maintains two independent channels:

### Channel 1: Persistent Service Channel (`CHANNEL_ID = "ForexMarketServiceChannel"`)
* **Importance:** `IMPORTANCE_LOW` (silent, non-intrusive).
* **Notification ID:** `1001` (Fixed).
* **Behavior:** Ongoing notification indicating real-time background market tracking is active. Cannot be swiped away by the user.

### Channel 2: High-Priority Price Alarms (`ALARM_CHANNEL_ID = "ForexPriceAlarmChannel"`)
* **Importance:** `IMPORTANCE_HIGH` (maximum visibility).
* **Notification ID Range:** `ALARM_NOTIFICATION_BASE_ID = 2000 + Math.abs(title.hashCode() % 1000)`.
* **Behavior:** Renders as a full heads-up notification card with action button `DISMISS ALARM`, overrides Do Not Disturb, and wakes the device screen.
* **Segregation Benefit:** By isolating alarm notifications to IDs $\ge 2000$, dismissing or clearing an alarm notification never terminates or replaces the persistent service notification `1001`.

---

## 3. Power Management & Doze Mode WakeLocks

When a device is left unattended, Android transitions into aggressive power-saving Doze modes. TenX maintains active status through:

1. **Partial WakeLock:**
   ```kotlin
   wakeLock = powerManager.newWakeLock(
       PowerManager.PARTIAL_WAKE_LOCK,
       "AlertApp:PerpetualForegroundWakeLock"
   ).apply {
       setReferenceCounted(false)
       acquire()
   }
   ```
   Keeps the device CPU running at baseline frequency while allowing the display to remain completely off, ensuring minimal battery consumption.
2. **Foreground Service Declaration:** Declared with Android 14+ compliant foreground service types (`dataSync`) in `AndroidManifest.xml`.
3. **Screen Wakeup on Alarm:** When an alert fires, `AlarmPlayer.kt` temporarily acquires a full screen wakeup lock (`FLAG_KEEP_SCREEN_ON | FLAG_TURN_SCREEN_ON | FLAG_SHOW_WHEN_LOCKED`) to present the alarm interface directly on the lockscreen.

---

## 4. Audio Playback & Do Not Disturb (DND) Bypass

Standard media audio streams (`STREAM_MUSIC`) are muted when the device is set to Do Not Disturb or Vibrate. TenX routes emergency price alarms through the Android Alarm Audio Stream:

Implementation in [AlarmPlayer.kt](file:///c:/Users/hp/Documents/Web-Projects/Alert-App/android/app/src/main/kotlin/com/example/alert_app/AlarmPlayer.kt):
```kotlin
val audioAttributes = AudioAttributes.Builder()
    .setUsage(AudioAttributes.USAGE_ALARM)
    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
    .build()

mediaPlayer?.apply {
    setAudioAttributes(audioAttributes)
    isLooping = looping
    start()
}
```
* **DND Bypass:** Android OS prioritizes `USAGE_ALARM` above all media rules, ensuring price alerts ring loudly even during active Do Not Disturb schedules.
* **Vibrator Pattern:** Synchronized dual-burst haptic feedback (`[0, 500, 200, 500] ms`) accompanies the audio playback.

---

## 5. In-Memory OHLC Pre-Caching

Evaluating technical indicators (e.g. 200-period EMA, Bollinger Bands, Stochastic) and candlestick patterns for multiple background alerts requires historical candle data. To eliminate serial network blocking:
* `fetchOhlcBars(symbol, timeframe, limit)` maintains a thread-safe `ConcurrentHashMap<String, Pair<Long, JSONArray>>` cache.
* **TTL:** 10 seconds.
* **Pre-Caching Step:** At the start of each polling loop, all active alerts and multi-step stages are scanned to extract distinct `(symbol, timeframe)` pairs, fetching required bars concurrently before sequential rule evaluation.

---

## 6. Self-Healing & Boot Persistence

Aggressive OEM battery management solutions (e.g., Xiaomi MIUI, Samsung OneUI, OnePlus OxygenOS) may attempt to kill background processes. TenX incorporates dual self-healing mechanisms:

1. **`BootAndAlarmReceiver.kt`:**
   * Listens for `android.intent.action.BOOT_COMPLETED`, `android.intent.action.LOCKED_BOOT_COMPLETED`, and `android.intent.action.QUICKBOOT_POWERON`.
   * Automatically invokes `startForegroundService` immediately upon phone boot without requiring the user to manually open the app.
2. **`AlarmWatchdog.kt`:**
   * Registers a repeating exact alarm with `AlarmManager.setExactAndAllowWhileIdle()`.
   * Periodically verifies that `AlertForegroundService` is actively running; if the process was killed, the watchdog restarts the service.
