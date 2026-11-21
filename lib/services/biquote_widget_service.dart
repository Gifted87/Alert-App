import 'package:flutter/material.dart';

import '../screens/economic_calendar_screen.dart';
import '../screens/market_movers_screen.dart';
import '../screens/financial_news_screen.dart';
import '../screens/currency_matrix_screen.dart';
import 'alert_manager.dart';

/// Opens genuine Biquote market features as native Flutter screens.
/// Powered directly by Biquote REST & SignalR WebSocket APIs.
class BiquoteWidgetService {
  static Future<void> openEconomicCalendar(
    BuildContext context, {
    ValueChanged<String>? onSelectSymbol,
    AlertManager? alertManager,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EconomicCalendarScreen(
          onSelectSymbol: onSelectSymbol,
          alertManager: alertManager,
        ),
      ),
    );
  }

  static Future<void> openMarketMovers(
    BuildContext context, {
    ValueChanged<String>? onSelectSymbol,
    AlertManager? alertManager,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarketMoversScreen(
          onSelectSymbol: onSelectSymbol,
          alertManager: alertManager,
        ),
      ),
    );
  }

  static Future<void> openFinancialNews(
    BuildContext context, {
    ValueChanged<String>? onSelectSymbol,
    AlertManager? alertManager,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FinancialNewsScreen(
          onSelectSymbol: onSelectSymbol,
          alertManager: alertManager,
        ),
      ),
    );
  }

  static Future<void> openCurrencyMatrix(
    BuildContext context, {
    ValueChanged<String>? onSelectSymbol,
    AlertManager? alertManager,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CurrencyMatrixScreen(
          onSelectSymbol: onSelectSymbol,
          alertManager: alertManager,
        ),
      ),
    );
  }
}
