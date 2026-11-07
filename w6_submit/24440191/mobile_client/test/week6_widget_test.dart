// Part 1: widget tests. Run with:  flutter test test/week6_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/week6/app.dart';
import 'fakes.dart';

void main() {
  // Example (given): success state with a fake repository.
  testWidgets('shows items after Refresh', (tester) async {
    await tester.pumpWidget(Week6App(repo: FakeRepo()));
    expect(find.text('Tap Refresh'), findsOneWidget);

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('Item 1'), findsOneWidget);
    expect(find.text('Item 2'), findsOneWidget);
  });

  testWidgets('shows error state', (tester) async {
    await tester.pumpWidget(Week6App(repo: FailingRepo()));
    // TODO 2: tap 'Refresh', pumpAndSettle(),
    // then expect the text 'Could not load' exactly once.
    // Replace the fail() line below.
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load'), findsOneWidget);
  });

  // Optional extension: the loading state with SlowRepo.
  // A spinner never settles, so use tester.pump(), not pumpAndSettle().
  // Then call repo.itemsCompleter.complete(sampleItems) and check the list.
}
