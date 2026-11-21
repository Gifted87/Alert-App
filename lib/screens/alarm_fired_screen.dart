import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/market_models.dart';
import '../services/alarm_service.dart';
import '../services/settings_provider.dart';

class AlarmFiredScreen extends StatefulWidget {
  final PriceAlert alert;
  final double triggerPrice;
  final AlarmService alarmService;
  final VoidCallback onDismiss;
  final VoidCallback onSnooze;
  final ValueChanged<String>? onOpenTerminal;

  const AlarmFiredScreen({
    super.key,
    required this.alert,
    required this.triggerPrice,
    required this.alarmService,
    required this.onDismiss,
    required this.onSnooze,
    this.onOpenTerminal,
  });

  @override
  State<AlarmFiredScreen> createState() => _AlarmFiredScreenState();
}

class _AlarmFiredScreenState extends State<AlarmFiredScreen>
    with SingleTickerProviderStateMixin {
  late Timer _clockTimer;
  late DateTime _currentTime;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Slide to dismiss state
  double _dragPosition = 0.0;
  final double _thumbSize = 54.0;
  final double _trackPadding = 5.0;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    const MethodChannel('com.example.alert_app/alarm').invokeMethod(
      'setAlertWindowMode',
      {'enabled': true, 'wakeScreen': SettingsProvider().screenWakeup},
    );
    _currentTime = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    const MethodChannel('com.example.alert_app/alarm')
        .invokeMethod('setAlertWindowMode', {'enabled': false});
    _clockTimer.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    if (_isDismissing) return;
    _isDismissing = true;
    HapticFeedback.heavyImpact();
    widget.onDismiss();
    if (mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {
        Navigator.of(context).pop();
      }
    }
  }

  void _handleSnooze() {
    if (_isDismissing) return;
    _isDismissing = true;
    HapticFeedback.mediumImpact();
    widget.alarmService.stopAlarm();
    widget.onSnooze();
    if (mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {
        Navigator.of(context).pop();
      }
    }
  }

  void _handleOpenTerminal() {
    if (_isDismissing) return;
    _isDismissing = true;
    HapticFeedback.selectionClick();
    widget.alarmService.stopAlarm();
    final sym = widget.alert.symbol;
    if (mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {
        Navigator.of(context).pop();
      }
    }
    widget.onOpenTerminal?.call(sym);
  }

  String _getHeadline() {
    final a = widget.alert;
    if (a.isTimeScheduleAlert) {
      return a.eventName != null ? a.eventName! : '${a.symbol} Event Release';
    }
    if (a.isPatternAlert) {
      return '${a.symbol} ${a.candlestickPattern?.label ?? "Pattern"} Confirmed';
    }
    if (a.isIndicatorAlert) {
      return '${a.symbol} ${a.indicatorConfig?.summary ?? "Indicator Condition"}';
    }
    final conditionStr = a.condition == AlertCondition.crossesAbove
        ? 'crossed above'
        : a.condition == AlertCondition.crossesBelow
        ? 'crossed below'
        : 'hit target level';
    return '${a.symbol} $conditionStr';
  }

  String _getTag() {
    final a = widget.alert;
    if (a.isTimeScheduleAlert) return 'CALENDAR ALARM';
    if (a.isPatternAlert) return 'PATTERN ALARM';
    if (a.isIndicatorAlert) return 'INDICATOR ALARM';
    if (a.isMultiStepAlert) return 'STRATEGY CHAIN ALARM';
    return 'PRICE ALARM';
  }

  String _getDisplayPrice() {
    final a = widget.alert;
    if (a.isTimeScheduleAlert) {
      return a.scheduledTime != null
          ? DateFormat('HH:mm').format(a.scheduledTime!.toLocal())
          : 'NOW';
    }
    final p = widget.triggerPrice > 0 ? widget.triggerPrice : a.targetPrice;
    if (a.symbol.contains('JPY')) {
      return p.toStringAsFixed(3);
    } else if (a.symbol.contains('BTC') || a.symbol.contains('XAU')) {
      return p.toStringAsFixed(2);
    }
    return p.toStringAsFixed(5);
  }

  String _getSubDetails() {
    final a = widget.alert;
    if (a.isTimeScheduleAlert) {
      return '5m advance notice · ${a.symbol} scheduled release';
    }
    final trig = widget.triggerPrice > 0 ? widget.triggerPrice : a.targetPrice;
    final trigStr = a.symbol.contains('JPY')
        ? trig.toStringAsFixed(3)
        : trig.toStringAsFixed(5);
    final targetStr = a.formattedTarget();
    return 'Triggered at $trigStr · Target $targetStr · Time ${DateFormat('HH:mm:ss').format(_currentTime)}';
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, d MMMM').format(_currentTime);
    final timeStr = DateFormat('HH:mm').format(_currentTime);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Ambient Radial Gradient (Top Center)
            Positioned(
              left: -80,
              right: -80,
              top: 40,
              height: 580,
              child: IgnorePointer(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.0, -0.4),
                      radius: 0.75,
                      colors: [
                        Color(0x66FF9F0A),
                        Color(0x28FF453A),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // Main Content Area
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 18),

                    // Date & Big Digital Clock
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xB3EBEBF5),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 78,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.05 * 78,
                        height: 1.05,
                        color: Colors.white,
                      ),
                    ),

                    const Spacer(flex: 2),

                    // Center Animated Concentric Pulse Rings & Bell Badge
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        final scale = _pulseAnimation.value;
                        return SizedBox(
                          width: 200,
                          height: 200,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer pulse ring
                              Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: 200,
                                  height: 200,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0x59FF9F0A),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              // Middle pulse ring
                              Transform.scale(
                                scale: 1.0 + (scale - 1.0) * 0.5,
                                child: Container(
                                  width: 148,
                                  height: 148,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0x99FF9F0A),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              // Center glowing bell badge
                              Container(
                                width: 98,
                                height: 98,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFFF9F0A),
                                      Color(0xFFFF453A),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x8CFF6428),
                                      blurRadius: 48,
                                      spreadRadius: 4,
                                      offset: Offset(0, 16),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.notifications_active_rounded,
                                    color: Colors.white,
                                    size: 46,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const Spacer(flex: 2),

                    // Price Alarm Tag
                    Text(
                      _getTag(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                        color: Color(0xFFFFB340),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Headline (e.g. EUR/USD crossed above)
                    Text(
                      _getHeadline(),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Massive Price / Target
                    Text(
                      _getDisplayPrice(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 44,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.05 * 44,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Monospace quote details
                    Text(
                      _getSubDetails(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Color(0x99EBEBF5),
                      ),
                    ),

                    const Spacer(flex: 3),

                    // Slide to Dismiss Track
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final trackWidth = constraints.maxWidth;
                        final maxDrag =
                            trackWidth - _thumbSize - (_trackPadding * 2);

                        return Container(
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0x24FFFFFF),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                              color: const Color(0x1FFFFFFF),
                              width: 1,
                            ),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Instruction label
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(width: 44),
                                  Text(
                                    'Slide to dismiss alarm',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(
                                        alpha: (1.0 - (_dragPosition / maxDrag))
                                            .clamp(0.2, 0.85),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              // Draggable circular thumb
                              Positioned(
                                left: _trackPadding + _dragPosition,
                                top: _trackPadding,
                                child: GestureDetector(
                                  onHorizontalDragUpdate: (details) {
                                    setState(() {
                                      _dragPosition =
                                          (_dragPosition + details.delta.dx)
                                              .clamp(0.0, maxDrag);
                                    });
                                  },
                                  onHorizontalDragEnd: (details) {
                                    if (_dragPosition >= maxDrag * 0.75) {
                                      setState(() {
                                        _dragPosition = maxDrag;
                                      });
                                      _handleDismiss();
                                    } else {
                                      setState(() {
                                        _dragPosition = 0.0;
                                      });
                                    }
                                  },
                                  child: Container(
                                    width: _thumbSize,
                                    height: _thumbSize,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0x66000000),
                                          blurRadius: 10,
                                          offset: Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.black,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 12),

                    // Snooze 5 min & Open Terminal Buttons
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _handleSnooze,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0x1FFFFFFF),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(26),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                'Snooze ${SettingsProvider().defaultSnoozeMinutes} min',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _handleOpenTerminal,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0A84FF),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(26),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Open Terminal',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
