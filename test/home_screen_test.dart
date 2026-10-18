import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:talksimple/screens/first_then_screen.dart';
import 'package:talksimple/screens/home_screen.dart';

void main() {
  testWidgets('Shows the three board type choices', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.text('Zuerst - Dann'), findsOneWidget);
    expect(find.text('Zwei Auswahl'), findsOneWidget);
    expect(find.text('kommt bald'), findsOneWidget);
    expect(find.text('Frei gestaltbares Board'), findsOneWidget);
  });

  testWidgets('Tapping Zuerst - Dann opens the FirstThenScreen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    await tester.tap(find.text('Zuerst - Dann'));
    await tester.pumpAndSettle();

    expect(find.byType(FirstThenScreen), findsOneWidget);
    expect(find.text('Zuerst'), findsOneWidget);
    expect(
      find.text('Gedrückt halten und sagen,\nwas du sehen möchtest'),
      findsOneWidget,
    );
  });
}
