// Part 1: unit tests. Run with:  flutter test test/week6_unit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../lib/week6/item.dart';
import '../lib/week6/item_repository.dart';
import '../lib/week6/retry_policy.dart';

void main() {
  // Example (given): pure logic, no Flutter, no network.
  test('backoff doubles each retry', () {
    const p = RetryPolicy(baseMs: 200, maxRetries: 3);
    expect(p.delaysMs(), [200, 400, 800]);
  });

  test('backoff is capped at maxDelayMs', () {
    const p = RetryPolicy(baseMs: 1000, maxRetries: 4, maxDelayMs: 3000);
    expect(p.delaysMs(), [1000, 2000, 3000, 3000]);
  });

  test('404 is not retried', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('', 404);
    });
    final repo = ApiItemRepository(client: client, baseUrl: 'http://test');

    // TODO 1: expect fetchItems() to throw an ApiException,
    // then expect exactly one call. Replace the fail() line below.
    await expectLater(repo.fetchItems(), throwsA(isA<ApiException>()));
    expect(calls, 1);
  });

  // Optional extension: a 503 is retried 3 times (4 calls), then fails.
  // Add: import 'package:fake_async/fake_async.dart';
  // Wrap the test body in fakeAsync((async) { ... }) and call
  // async.elapse(const Duration(seconds: 5)) so the backoff runs instantly.

  // Optional extension: a 200 with body '{"oops":' gives a FormatException.

  test('decodeItems parses a list', () {
    final items = decodeItems('[{"id":1,"name":"A","tags":["x"]}]');
    expect(items.single.name, 'A');
    expect(items.single.tags, ['x']);
  });
}
