// FINAL version (Part 4 onward): retry with backoff + idempotency keys.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/item.dart';
import 'api_exceptions.dart';
import 'retry.dart';

class ApiClient {
  final http.Client _http;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _http.close();
  }
  final Duration timeout;
  final RetryPolicy retryPolicy;

  ApiClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 2),
    this.retryPolicy = const RetryPolicy(),
  }) : _ownsClient = client == null, _http = client ?? http.Client();

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  /// Sends one request and classifies transport and HTTP status failures.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException('Timed out after ${timeout.inMilliseconds} ms',
          retryable: true);
    } on SocketException catch (e) {
      throw ApiException('Network error: ${e.message}', retryable: true);
    } on http.ClientException catch (e) {
      throw ApiException('Network error: ${e.message}', retryable: true);
    }

    if (res.statusCode >= 500 && res.statusCode <= 599) {
      throw ApiException('Server error',
          statusCode: res.statusCode, retryable: true);
    }
    if (res.statusCode >= 400) {
      throw ApiException('Client error: ${res.body}',
          statusCode: res.statusCode);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException('Unexpected HTTP status', statusCode: res.statusCode);
    }
    return res;
  }

  /// Decodes JSON, turning a broken body into a non-retryable ApiException.
  dynamic _decode(http.Response res) {
    try {
      return jsonDecode(res.body);
    } on FormatException {
      throw ApiException('Malformed JSON from server',
          statusCode: res.statusCode);
    }
  }

  List<Item> _items(http.Response res) {
    final data = _decode(res);
    if (data is! List) throw ApiException('Expected an item list');
    return data.map((value) => _itemValue(value)).toList();
  }

  Item _itemValue(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw ApiException('Expected an item object');
    }
    try {
      return Item.fromJson(value);
    } on FormatException catch (e) {
      throw ApiException('Invalid item response: ${e.message}');
    }
  }

  void _checkItem(String name, double price) {
    if (name.trim().isEmpty || name.trim().length > 120 ||
        !price.isFinite || price < 0) {
      throw ApiException('Enter a name (1-120 characters) and a nonnegative price');
    }
  }

  Future<List<Item>> getItems() => withRetry(() async {
        final res = await _send(() => _http.get(_uri('/items')));
        return _items(res);
      }, retryPolicy);

  /// POST is only safe to retry because every attempt carries the SAME key.
  Future<Item> createItem(
    String name,
    double price, {
    double failRate = 0,
    bool useIdempotencyKey = true,
  }) {
    _checkItem(name, price);
    // Generated once, OUTSIDE the retry loop.
    final key = useIdempotencyKey ? newIdempotencyKey() : null;
    return withRetry(() async {
      final res = await _send(() => _http.post(
            _uri('/items', failRate > 0 ? {'fail_rate': '$failRate'} : null),
            headers: {
              'Content-Type': 'application/json',
              if (key != null) 'Idempotency-Key': key,
            },
            body: jsonEncode({'name': name, 'price': price}),
          ));
      return _itemValue(_decode(res));
    }, retryPolicy);
  }

  // ---- Fault-injection test endpoints ----
  Future<void> getSlow(double delay) async {
    _decode(await _send(() => _http.get(_uri('/slow', {'delay': '$delay'}))));
  }

  Future<void> getFlaky(
    double failRate, {
    RetryPolicy? policy,
    void Function()? onAttempt,
  }) =>
      withRetry(() async {
        _decode(await _send(
            () => _http.get(_uri('/flaky', {'fail_rate': '$failRate'}))));
      }, policy ?? retryPolicy, onAttempt: onAttempt);

  Future<void> getBadJson() async {
    _decode(await _send(() => _http.get(_uri('/bad-json'))));
  }

  /// Resets the backend's items and random seed (repeatable experiments).
  Future<void> reset(int seed) async {
    await _send(() => _http.post(_uri('/reset', {'seed': '$seed'})));
  }
}
