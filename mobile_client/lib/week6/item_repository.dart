import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'item.dart';
import 'retry_policy.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($message)';
}

/// The rest of the app only knows this interface (lecture slide 20).
abstract class ItemRepository {
  Future<List<Item>> fetchItems();
  Future<Item> fetchItem(int id);
}

class ApiItemRepository implements ItemRepository {
  ApiItemRepository({
    required this.client,
    required this.baseUrl,
    this.policy = const RetryPolicy(),
    this.timeout = const Duration(seconds: 5),
    this.detailDelayMs = 3000,
  });

  final http.Client client;
  final String baseUrl;
  final RetryPolicy policy;
  final Duration timeout;

  /// The server waits this long before answering a detail request (Part 2).
  final int detailDelayMs;

  @override
  Future<List<Item>> fetchItems() async =>
      decodeItems(await getWithRetry(Uri.parse('$baseUrl/w6/items')));

  @override
  Future<Item> fetchItem(int id) async {
    final body = await getWithRetry(
      Uri.parse('$baseUrl/w6/items/$id?delay_ms=$detailDelayMs'),
    );
    return Item.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Raw body for the Part 3 experiment, so decoding can be timed separately.
  Future<String> fetchBulkBody(int n) => getWithRetry(
        Uri.parse('$baseUrl/w6/bulk?n=$n'),
        timeout: const Duration(seconds: 30),
      );

  /// GET with timeout and retry with exponential backoff (Week 4).
  Future<String> getWithRetry(Uri uri, {Duration? timeout}) async {
    final delays = policy.delaysMs();
    for (var attempt = 0;; attempt++) {
      final lastAttempt = attempt >= delays.length;
      try {
        final r = await client.get(uri).timeout(timeout ?? this.timeout);
        if (r.statusCode == 200) return utf8.decode(r.bodyBytes);
        if (!policy.isRetryableStatus(r.statusCode) || lastAttempt) {
          throw ApiException('HTTP ${r.statusCode}', statusCode: r.statusCode);
        }
      } on TimeoutException {
        if (lastAttempt) throw const ApiException('Timed out');
      } on http.ClientException catch (e) {
        if (lastAttempt) throw ApiException('Network error: ${e.message}');
      }
      await Future<void>.delayed(Duration(milliseconds: delays[attempt]));
    }
  }
}
