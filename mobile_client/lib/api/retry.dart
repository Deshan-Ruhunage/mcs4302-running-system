import 'dart:math';

import 'api_exceptions.dart';

class RetryPolicy {
  final int maxRetries;
  final Duration baseDelay;
  final double jitter; // 0.2 = +/-20%

  const RetryPolicy({
    this.maxRetries = 3,
    this.baseDelay = const Duration(milliseconds: 200),
    this.jitter = 0.2,
  }) : assert(maxRetries >= 0), assert(jitter >= 0 && jitter <= 1);

  static const none = RetryPolicy(maxRetries: 0);
}

final _random = Random();

/// Runs [action], retrying retryable ApiExceptions with exponential backoff:
/// waits base * 2^attempt (+/- jitter) -> 200, 400, 800 ms by default.
/// [onAttempt] is called before every HTTP attempt (used to count calls).
Future<T> withRetry<T>(
  Future<T> Function() action,
  RetryPolicy policy, {
  void Function()? onAttempt,
}) async {
  var attempt = 0;
  while (true) {
    onAttempt?.call();
    try {
      return await action();
    } on ApiException catch (e) {
      if (!e.retryable || attempt >= policy.maxRetries) rethrow;
      final backoffMs = policy.baseDelay.inMilliseconds * pow(2, attempt);
      final jitterMs =
          backoffMs * policy.jitter * (_random.nextDouble() * 2 - 1);
      await Future<void>.delayed(
          Duration(milliseconds: (backoffMs + jitterMs).round()));
      attempt++;
    }
  }
}

/// Random 128-bit hex key, generated ONCE per logical operation.
String newIdempotencyKey() {
  final r = Random.secure();
  return List.generate(
      16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
