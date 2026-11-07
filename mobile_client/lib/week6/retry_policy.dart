import 'dart:math';

/// Exponential backoff without jitter, so tests are deterministic.
/// (Week 4 added jitter; you can add it back with an injectable Random.)
class RetryPolicy {
  const RetryPolicy({
    this.baseMs = 200,
    this.maxRetries = 3,
    this.maxDelayMs = 5000,
  });

  final int baseMs;
  final int maxRetries;
  final int maxDelayMs;

  /// Delay before retry 1, 2, 3, ... e.g. [200, 400, 800].
  List<int> delaysMs() => [
        for (var i = 0; i < maxRetries; i++) min(baseMs * (1 << i), maxDelayMs),
      ];

  /// Server errors, timeouts and rate limits may succeed later.
  /// Other 4xx errors will not, so they are not retried.
   bool isRetryableStatus(int code) => code >= 500 || code == 408 || code == 429;
}
