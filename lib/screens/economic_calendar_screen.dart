import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/alert_manager.dart';
import '../services/market_data_api.dart';
import '../services/analysis_orchestrator.dart';
import '../widgets/tenx_toast.dart';

class EconomicCalendarScreen extends StatefulWidget {
  final ValueChanged<String>? onSelectSymbol;
  final AlertManager? alertManager;

  const EconomicCalendarScreen({
    super.key,
    this.onSelectSymbol,
    this.alertManager,
  });

  @override
  State<EconomicCalendarScreen> createState() => _EconomicCalendarScreenState();
}

class _EconomicCalendarScreenState extends State<EconomicCalendarScreen> {
  // Currency Filter: All, USD, EUR, GBP, JPY, AUD
  int _selectedCurrencyIndex = 0;
  final List<String> _currencies = ['All', 'USD', 'EUR', 'GBP', 'JPY', 'AUD'];

  // Day Selector: -1 for All Dates, 0 for Today, 1 for Tomorrow, etc.
  int _selectedDayIndex = 0; // Default to Current Day (Today)
  late List<DateTime> _futureDays;

  bool _loading = true;
  String? _error;
  List<CalendarEvent> _events = [];

  final Set<String> _alertedEventIds = {};

  @override
  void initState() {
    super.initState();
    _initWeekDays();
    _load();
    // Sync already-scheduled event IDs from persisted AlertManager state
    _syncAlertedEventIds();
  }

  void _syncAlertedEventIds() {
    final am = widget.alertManager;
    if (am != null) {
      for (final a in am.alerts) {
        if (a.isActive && a.isTimeScheduleAlert && a.eventId != null) {
          _alertedEventIds.add(a.eventId!);
        }
      }
    }
  }

  void _initWeekDays() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // ONLY contain days starting from current day into the future (14 upcoming days)
    _futureDays = List.generate(14, (i) => today.add(Duration(days: i)));
    _selectedDayIndex = 0; // Default to Current Day (Today)
  }

  String _formatEventDate(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(local.year, local.month, local.day);
    final diffDays = eventDay.difference(today).inDays;

    final timeStr = DateFormat('HH:mm').format(local);
    if (diffDays == 0) {
      return 'Today · $timeStr';
    } else if (diffDays == 1) {
      return 'Tomorrow · $timeStr';
    } else if (diffDays == -1) {
      return 'Yesterday · $timeStr';
    } else {
      return '${DateFormat("EEE, MMM d").format(local)} · $timeStr';
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final selectedCur = _currencies[_selectedCurrencyIndex];
      final countries = selectedCur == 'All'
          ? 'US,EU,GB,JP,CA,AU,CH'
          : _mapCurrencyToCountry(selectedCur);

      final events = await MarketDataApi.getCalendar(
        countries: countries,
        importance: 'low',
      );

      if (mounted) {
        setState(() {
          _events = events;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  String _mapCurrencyToCountry(String cur) {
    switch (cur.toUpperCase()) {
      case 'USD':
        return 'US';
      case 'EUR':
        return 'EU,DE,FR';
      case 'GBP':
        return 'GB';
      case 'JPY':
        return 'JP';
      case 'AUD':
        return 'AU';
      default:
        return 'US,EU,GB,JP';
    }
  }

  List<CalendarEvent> _getFilteredEvents() {
    final selectedCur = _currencies[_selectedCurrencyIndex];

    return _events.where((e) {
      final matchCurrency =
          selectedCur == 'All' ||
          e.currency.toUpperCase() == selectedCur.toUpperCase() ||
          e.countryCode.toUpperCase() == _mapCurrencyToCountry(selectedCur);

      if (!matchCurrency) return false;

      // If "All Upcoming Dates" selected (-1), show all events
      if (_selectedDayIndex < 0 || _selectedDayIndex >= _futureDays.length) {
        return true;
      }

      final selectedDate = _futureDays[_selectedDayIndex];
      final eventLocal = e.time.toLocal();

      return eventLocal.year == selectedDate.year &&
          eventLocal.month == selectedDate.month &&
          eventLocal.day == selectedDate.day;
    }).toList();
  }

  void _scheduleEventAlert(CalendarEvent event) {
    final alertTime = event.time.subtract(const Duration(minutes: 5));
    // Create a real time-based alert via AlertManager (persisted & background-evaluated)
    if (widget.alertManager != null) {
      widget.alertManager!.addScheduledCalendarAlert(
        eventId: event.id,
        eventName: event.name,
        currency: event.currency,
        eventTime: event.time,
        minutesBefore: 5,
      );
    }

    setState(() {
      _alertedEventIds.add(event.id);
    });

    final alertDateStr = _formatEventDate(alertTime);
    TenXToast.show(
      context,
      title: 'Alert Scheduled',
      subtitle: '$alertDateStr · 5m before ${event.name} (${event.currency})',
      icon: Icons.notifications_active_rounded,
      iconColor: const Color(0xFFFFB340),
      iconBgColor: const Color(0x33FF9F0A),
    );
  }

  void _showEventDetails(CalendarEvent event) {
    final correlatedPairs = _getCorrelatedPairs(event.currency);
    final dateTimeStr = DateFormat('EEEE, MMMM d, yyyy · HH:mm (z)')
        .format(event.time.toLocal());
    final isAlerted = _alertedEventIds.contains(event.id);
    final primaryPair = correlatedPairs.isNotEmpty
        ? correlatedPairs.first
        : 'EURUSD';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          event.currency.isNotEmpty
                              ? event.currency
                              : event.countryCode,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        event.importance.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: event.importance.toLowerCase() == 'high'
                              ? const Color(0xFFFF6961)
                              : const Color(0xFFFFB340),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _formatEventDate(event.time),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0x9EEBEBF5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                event.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (event.actual != null) ...[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ACTUAL',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0x57EBEBF5),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${event.actual!}${event.unit ?? ""}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF43E06A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (event.forecast != null) ...[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'FORECAST',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0x57EBEBF5),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${event.forecast!}${event.unit ?? ""}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (event.previous != null) ...[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PREVIOUS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0x57EBEBF5),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${event.previous!}${event.unit ?? ""}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'CORRELATED INSTRUMENTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.99,
                  color: Color(0x9EEBEBF5),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: correlatedPairs.map((pair) {
                  return ActionChip(
                    backgroundColor: const Color(0xFF2C2C2E),
                    label: Text(
                      pair,
                      style: const TextStyle(
                        color: Color(0xFF0A84FF),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (widget.onSelectSymbol != null) {
                        widget.onSelectSymbol!(pair);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'SCHEDULED TIME',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.99,
                  color: Color(0x9EEBEBF5),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                dateTimeStr,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        AnalysisOrchestrator()
                            .runDeliberation(
                              symbol: primaryPair,
                              timeframe: '1h',
                              customDirective:
                                  'Pre-event macro impact analysis for ${event.name} (${event.currency}). Evaluate liquidity, volatility risk, and key levels.',
                            )
                            .catchError((_) => null);
                        TenXToast.show(
                          context,
                          title: 'AI Deliberation Started',
                          subtitle:
                              'Synthesizing macro impact on $primaryPair...',
                          icon: Icons.psychology_rounded,
                        );
                      },
                      icon: const Icon(Icons.psychology_rounded, size: 18),
                      label: Text(
                        'AI Briefing ($primaryPair)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF64D2FF),
                        side: const BorderSide(color: Color(0x3364D2FF)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isAlerted
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _scheduleEventAlert(event);
                            },
                      icon: Icon(
                        isAlerted
                            ? Icons.check_circle_rounded
                            : Icons.notifications_active_rounded,
                        size: 18,
                      ),
                      label: Text(
                        isAlerted ? 'SCHEDULED' : 'ALERT 5M BEFORE',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2C2C2E),
                        foregroundColor: const Color(0xFFFFB340),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _getCorrelatedPairs(String cur) {
    switch (cur.toUpperCase()) {
      case 'USD':
        return ['EURUSD', 'GBPUSD', 'USDJPY', 'XAUUSD', 'USDCAD'];
      case 'EUR':
        return ['EURUSD', 'EURGBP', 'EURJPY', 'EURAUD', 'EURCHF'];
      case 'GBP':
        return ['GBPUSD', 'EURGBP', 'GBPJPY', 'GBPAUD'];
      case 'JPY':
        return ['USDJPY', 'EURJPY', 'GBPJPY', 'AUDJPY'];
      case 'AUD':
        return ['AUDUSD', 'EURAUD', 'AUDJPY', 'AUDNZD'];
      case 'CAD':
        return ['USDCAD', 'EURCAD', 'CADJPY'];
      case 'CHF':
        return ['USDCHF', 'EURCHF', 'CHFJPY'];
      default:
        return ['EURUSD', 'GBPUSD', 'USDJPY'];
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final filteredEvents = _getFilteredEvents();

    // Find first high impact event for the Hero card
    CalendarEvent? heroEvent;
    for (final e in filteredEvents) {
      if (e.importance.toLowerCase() == 'high') {
        heroEvent = e;
        break;
      }
    }
    heroEvent ??= (filteredEvents.isNotEmpty ? filteredEvents.first : null);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: true,
        bottom: true,
        child: Column(
          children: [
            const SizedBox(height: 6),
            // Header: Title "Calendar" + "GMT+1"
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (canPop) ...[
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Padding(
                              padding: EdgeInsets.only(right: 12),
                              child: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                        const Text(
                          'Calendar',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.03 * 34,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'GMT+1',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0x9EEBEBF5),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_loading)
              const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0A84FF)),
              ),
            if (_error != null && _events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                child: Text(
                  'Live calendar sync: $_error',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0x57EBEBF5),
                  ),
                ),
              ),

            // Currency Filter Chips: All | USD | EUR | GBP | JPY | AUD
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _currencies.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (ctx, idx) {
                    final isSelected = _selectedCurrencyIndex == idx;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCurrencyIndex = idx;
                        });
                        _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Center(
                          child: Text(
                            _currencies[idx],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.black
                                  : const Color(0x9EEBEBF5),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Future Day Selector Chips: ALL | TODAY | TMRW | MON 19 | TUE 20 ...
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _futureDays.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final isAll = i == 0;
                    final dayIdx = isAll ? -1 : i - 1;
                    final isSelected = _selectedDayIndex == dayIdx;

                    if (isAll) {
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedDayIndex = -1;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 58,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF0A84FF)
                                : const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF0A84FF)
                                  : const Color(0x17FFFFFF),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'ALL',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0x9EEBEBF5),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'DATES',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0x57EBEBF5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final dt = _futureDays[i - 1];
                    final isToday = i - 1 == 0;
                    final isTomorrow = i - 1 == 1;
                    final dayName = isToday
                        ? 'TODAY'
                        : (isTomorrow
                              ? 'TMRW'
                              : DateFormat('EEE').format(dt).toUpperCase());
                    final dayNum = dt.day.toString();
                    final monthName = DateFormat('MMM')
                        .format(dt)
                        .toUpperCase();

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedDayIndex = i - 1;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 62,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF0A84FF)
                              : const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF0A84FF)
                                : (isToday
                                      ? const Color(0x4D0A84FF)
                                      : const Color(0x17FFFFFF)),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              dayName,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: isSelected
                                    ? const Color(0xD9FFFFFF)
                                    : (isToday
                                          ? const Color(0xFF0A84FF)
                                          : const Color(0x9EEBEBF5)),
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              dayNum,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              monthName,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                                color: isSelected
                                    ? const Color(0xCCFFFFFF)
                                    : const Color(0x57EBEBF5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Scrollable Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                children: [
                  // FEATURED HIGH IMPACT EVENT (HERO CARD)
                  if (heroEvent != null) ...[
                    Builder(
                      builder: (context) {
                        final hero = heroEvent!;
                        final diff = hero.time.toLocal().difference(
                          DateTime.now(),
                        );
                        final String timeTag;
                        if (diff.isNegative) {
                          final past = diff.abs();
                          timeTag = past.inMinutes < 60
                              ? 'RELEASED ${past.inMinutes < 1 ? 1 : past.inMinutes}M AGO'
                              : 'RELEASED ${past.inHours}H AGO';
                        } else if (diff.inMinutes < 60) {
                          timeTag =
                              'IN ${diff.inMinutes < 1 ? 1 : diff.inMinutes}M';
                        } else {
                          timeTag =
                              'IN ${diff.inHours}H ${diff.inMinutes % 60}M';
                        }

                        return GestureDetector(
                          onTap: () => _showEventDetails(hero),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0x2EFF453A), Color(0xFF1C1C1E)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0x40FF453A),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          height: 22,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2C2C2E),
                                            borderRadius: BorderRadius.circular(
                                              7,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              hero.currency.isNotEmpty
                                                  ? hero.currency
                                                  : 'USD',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.4,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${hero.importance.toUpperCase()} IMPACT · $timeTag',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                hero.importance.toLowerCase() ==
                                                    'high'
                                                ? const Color(0xFFFF6961)
                                                : const Color(0xFFFFB340),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      _formatEventDate(hero.time),
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0x9EEBEBF5),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  hero.name.isNotEmpty
                                      ? hero.name
                                      : 'Economic Event',
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.4,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'FORECAST',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.8,
                                              color: Color(0x57EBEBF5),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            hero.forecast != null
                                                ? '${hero.forecast!}${hero.unit ?? ""}'
                                                : '–',
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'PREVIOUS',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.8,
                                              color: Color(0x57EBEBF5),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            hero.previous != null
                                                ? '${hero.previous!}${hero.unit ?? ""}'
                                                : '–',
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: () =>
                                          _scheduleEventAlert(hero),
                                      icon: const Icon(
                                        Icons.notifications_none_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Alert 5m before'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0x2EFF9F0A,
                                        ),
                                        foregroundColor: const Color(
                                          0xFFFFB340,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                        minimumSize: const Size(0, 36),
                                        elevation: 0,
                                        textStyle: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                  ],

                  // STANDARD EVENTS LIST
                  ..._buildStandardEventCards(filteredEvents, heroEvent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStandardEventCards(
    List<CalendarEvent> events,
    CalendarEvent? hero,
  ) {
    // If we have API events, filter out hero and map
    final others = events
        .where((e) => hero == null || e.id != hero.id)
        .toList();

    if (others.isNotEmpty) {
      return others.map((e) => _buildEventCard(e)).toList();
    }

    if (_loading) {
      return const [
        SizedBox(height: 40),
        Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0A84FF)),
          ),
        ),
      ];
    }

    if (hero == null) {
      final selectedDayStr =
          _selectedDayIndex >= 0 && _selectedDayIndex < _futureDays.length
          ? DateFormat('EEEE, MMM d').format(_futureDays[_selectedDayIndex])
          : 'the selected date';
      return [
        Container(
          margin: const EdgeInsets.only(top: 24),
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.event_busy_rounded,
                color: Color(0x57EBEBF5),
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                'No economic releases scheduled for $selectedDayStr',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0x9EEBEBF5),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedDayIndex = -1; // View all upcoming dates
                  });
                },
                icon: const Icon(Icons.calendar_month_rounded, size: 16),
                label: const Text('View All Upcoming Releases'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2C2C2E),
                  foregroundColor: const Color(0xFF0A84FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    return const [];
  }

  Widget _buildEventCard(CalendarEvent e) {
    final int impactBars = e.importance.toLowerCase() == 'high'
        ? 3
        : (e.importance.toLowerCase() == 'medium' ? 2 : 1);
    final isBeat = (e.actual ?? 0) >= (e.forecast ?? 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: () => _showEventDetails(e),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Center(
                        child: Text(
                          e.currency.isNotEmpty ? e.currency : e.countryCode,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildImpactBars(impactBars),
                  ],
                ),
                Text(
                  _formatEventDate(e.time),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0x9EEBEBF5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              e.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            if (e.forecast != null || e.actual != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (e.actual != null) ...[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ACTUAL',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: Color(0x57EBEBF5),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${e.actual!}${e.unit ?? ""}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isBeat
                                  ? const Color(0xFF43E06A)
                                  : const Color(0xFFFF6961),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (e.forecast != null) ...[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'FORECAST',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: Color(0x57EBEBF5),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${e.forecast!}${e.unit ?? ""}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (e.previous != null) ...[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PREVIOUS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: Color(0x57EBEBF5),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${e.previous!}${e.unit ?? ""}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImpactBars(int level) {
    Color c1;
    Color c2;
    Color c3;

    if (level == 3) {
      c1 = const Color(0xFFFF453A);
      c2 = const Color(0xFFFF453A);
      c3 = const Color(0xFFFF453A);
    } else if (level == 2) {
      c1 = const Color(0xFFFF9F0A);
      c2 = const Color(0xFFFF9F0A);
      c3 = const Color(0xFF3A3A3C);
    } else {
      c1 = const Color(0xFFFFD60A);
      c2 = const Color(0xFF3A3A3C);
      c3 = const Color(0xFF3A3A3C);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 4,
          height: 6,
          decoration: BoxDecoration(
            color: c1,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 2),
        Container(
          width: 4,
          height: 10,
          decoration: BoxDecoration(
            color: c2,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 2),
        Container(
          width: 4,
          height: 14,
          decoration: BoxDecoration(
            color: c3,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}
