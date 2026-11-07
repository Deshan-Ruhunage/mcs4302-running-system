import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'config.dart';
import 'task.dart';

/// Reply to one POST /w7/sync: 200 (task = result) or 409 (task = server's current copy).
class SyncReply {
  const SyncReply(this.status, this.task);
  final int status;
  final Task task;
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => 'ApiException: $message';
}

class Api {
  Api({this.baseUrl = kBaseUrl});

  final String baseUrl;
  final http.Client _client = http.Client();
  static const _uuid = Uuid();
  static const _timeout = Duration(seconds: 5);

  /// Counters for the measurement sheet; the sync engine resets them per sync.
  int syncCalls = 0;
  int retries = 0;

  /// Part 3 only: send a NEW idempotency key on each retry (the wrong way).
  bool newKeyOnRetry = false;

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Map<String, dynamic> _json(http.Response r) {
    if (r.statusCode >= 400) {
      throw ApiException('${r.request?.url.path} -> HTTP ${r.statusCode}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? q]) async =>
      _json(await _client.get(_u(path, q)).timeout(_timeout));

  Future<Map<String, dynamic>> _post(String path, Object body) async =>
      _json(await _client
          .post(_u(path),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(_timeout));

  // ------------------------------------------------------------ sync

  /// Push ONE outbox op. Retries 5xx and timeouts with exponential backoff
  /// (Week 4), reusing the same idempotency key unless [newKeyOnRetry].
  Future<SyncReply> push(OutboxOp op, String mode, Task local) async {
    var key = op.idemKey;
    for (var attempt = 0;; attempt++) {
      final body = <String, Object?>{
        'idem_key': key,
        'op': op.op,
        'task_id': op.taskId,
        if (mode == 'version') ...{
          'base_version': op.baseVersion,
          'fields': op.fields, // only what changed
        } else ...{
          'record': {'title': local.title, 'status': local.status}, // whole record
          'updated_at': op.updatedAt, // device clock
        },
      };
      try {
        syncCalls++;
        final r = await _client
            .post(_u('/sync'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(body))
            .timeout(_timeout);
        if (r.statusCode == 200 || r.statusCode == 409) {
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          return SyncReply(
              r.statusCode, Task.fromJson(j['task'] as Map<String, dynamic>));
        }
        if (r.statusCode < 500) {
          throw ApiException('/sync -> HTTP ${r.statusCode}: ${r.body}');
        }
        // 5xx: fall through to retry
      } on TimeoutException {
        // retry
      } on SocketException {
        // retry
      } on http.ClientException {
        // retry (package:http wraps connection errors in ClientException)
      }
      if (attempt >= 3) throw ApiException('/sync failed after ${attempt + 1} tries');
      retries++;
      if (newKeyOnRetry) key = _uuid.v4();
      await Future<void>.delayed(Duration(milliseconds: 300 * (1 << attempt)));
    }
  }

  /// Delta pull: everything after [since], plus the new cursor.
  Future<(List<Task>, int)> changes(int since) async {
    final j = await _get('/changes', {'since': '$since'});
    final list = (j['changes'] as List)
        .map((c) => Task.fromJson((c as Map<String, dynamic>)['task'] as Map<String, dynamic>))
        .toList();
    return (list, j['cursor'] as int);
  }

  /// Full re-download of the dataset (first run and Reset run).
  Future<(List<Task>, int)> allTasks() async {
    final j = await _get('/tasks');
    final list = (j['tasks'] as List)
        .map((t) => Task.fromJson(t as Map<String, dynamic>))
        .toList();
    return (list, j['cursor'] as int);
  }

  // ------------------------------------------------------------ lab controls

  Future<String> mode() async => (await _get('/mode'))['mode'] as String;

  Future<void> reset(String mode) => _post('/reset', {'mode': mode});

  Future<void> phoneBEdit(String field, String value) => _post(
      '/phone-b/edit',
      {'task_id': 'task-42', 'field': field, 'value': value, 'clock_skew_min': 10});

  Future<void> dropNextReply() => _post('/fault/drop-next-reply', {});

  Future<Task> serverTask(String id) async =>
      Task.fromJson((await _get('/tasks/$id'))['task'] as Map<String, dynamic>);

  /// Per-endpoint body bytes counted by the server.
  Future<Map<String, dynamic>> stats() async =>
      (await _get('/stats'))['endpoints'] as Map<String, dynamic>;
}
