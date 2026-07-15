import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chicksprintgame/state/route_mode.dart';

void main() {
  test('RouteMode restore round-trips', () {
    for (final mode in RouteMode.values) {
      expect(RouteMode.restore(mode.storageValue), mode);
    }
    expect(RouteMode.restore(null), RouteMode.fresh);
    expect(RouteMode.restore('bogus'), RouteMode.fresh);
  });

  testWidgets('MaterialApp mounts a bare widget', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
