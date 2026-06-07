import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Smoke test', (WidgetTester tester) async {
    // Verify that the test harness and basic widget compilation work
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Finance App'))));
    expect(find.text('Finance App'), findsOneWidget);
  });
}
