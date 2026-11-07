// Part 2: regression test for the seeded defect.
// Run with:  flutter test test/week6_regression_test.dart
// It must FAIL on the original code and PASS after your fix.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/week6/detail_page.dart';
import 'fakes.dart';

void main() {
  // Given: you do not need to edit this test.
  testWidgets('response after leaving the page does not crash',
      (tester) async {
    final repo = SlowRepo();

    // 1. Open the detail page. The request is now waiting.
    await tester.pumpWidget(
      MaterialApp(home: ItemDetailPage(repo: repo, id: 1)),
    );

    // 2. The user leaves: replace the page, which disposes its State.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    // 3. The response arrives afterwards.
    repo.itemCompleter.complete(sampleItems.first);
    await tester.pump();

    // 4. No "setState() called after dispose()" error.
    expect(tester.takeException(), isNull);
  });
}
