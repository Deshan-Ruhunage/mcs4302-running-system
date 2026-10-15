import 'api/api_client.dart';
import 'api/api_exceptions.dart';
import 'api/retry.dart';

class ExperimentResult {
  final String label;
  final int seed;
  final int n, successes, httpCalls;
  final double meanMs, p95Ms;

  ExperimentResult(this.label, this.n, this.successes, this.httpCalls,
      this.meanMs, this.p95Ms, this.seed);

  double get successRate => 100 * successes / n;

  String toCsv() => '"${label.replaceAll('"', '""')}",$seed,$n,${successRate.toStringAsFixed(1)},' 
      '${meanMs.toStringAsFixed(0)},${p95Ms.toStringAsFixed(0)},$httpCalls';
}

/// Nearest-rank percentile.
double percentile(List<double> values, double p) {
  if (values.isEmpty || p <= 0 || p > 100) {
    throw ArgumentError('Percentile requires values and 0 < p <= 100');
  }
  final sorted = [...values]..sort();
  final rank = (p / 100 * sorted.length).ceil() - 1;
  return sorted[rank.clamp(0, sorted.length - 1)];
}

/// Sends [n] sequential requests to /flaky and measures each LOGICAL request
/// (first attempt until final success/failure, including backoff waits).
Future<ExperimentResult> runExperiment(
  ApiClient api, {
  required String label,
  required double failRate,
  required RetryPolicy policy,
  int n = 50,
  int seed = 42,
}) async {
  if (n <= 0) throw ArgumentError.value(n, 'n', 'Must be positive');
  await api.reset(seed);
  final latencies = <double>[];
  var successes = 0;
  var httpCalls = 0;

  for (var i = 0; i < n; i++) {
    final sw = Stopwatch()..start();
    try {
      await api.getFlaky(failRate,
          policy: policy, onAttempt: () => httpCalls++);
      successes++;
    } on ApiException {
      // Final failure after all retries; latency is still recorded.
    }
    sw.stop();
    latencies.add(sw.elapsedMicroseconds / 1000);
  }

  final mean = latencies.reduce((a, b) => a + b) / n;
  return ExperimentResult(
      label, n, successes, httpCalls, mean, percentile(latencies, 95), seed);
}
