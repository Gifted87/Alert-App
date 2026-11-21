import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alert_app/main.dart';

void main() {
  testWidgets('TenXApp launches splash screen matching new design', (WidgetTester tester) async {
    await tester.pumpWidget(const TenXApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('TenX'), findsWidgets);
    expect(find.text('Institutional Trading Terminal'), findsOneWidget);
    expect(find.text('Network connected'), findsOneWidget);
    expect(find.text('Biquote live feed'), findsOneWidget);
    expect(find.text('Zero synthetic data · Live broker prices only'), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);

    // Cleanly unmount to cancel remaining timers
    await tester.pumpWidget(const SizedBox());
  });
}
