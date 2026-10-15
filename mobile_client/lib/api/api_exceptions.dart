/// One exception type for every API failure.
/// [retryable] says whether sending the same request again might succeed.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool retryable;

  ApiException(this.message, {this.statusCode, this.retryable = false});

  @override
  String toString() =>
      statusCode == null ? message : 'HTTP $statusCode: $message';
}
