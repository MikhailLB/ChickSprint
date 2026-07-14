import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chicksprintgame/main.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const ChickSprintApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
