import 'api.dart';
import 'local_db.dart';
import 'task.dart';

/// What one sync did. These numbers go on the measurement sheet.
class SyncReport {
  int pushed = 0; // ops accepted first time
  int conflicts = 0; // 409s received
  int merged = 0; // conflicts resolved by field-level merge
  int unresolved = 0; // conflicts parked for the user
  int pulled = 0; // changes received by the pull
  int syncCalls = 0; // POST /sync requests, including retries
  int retries = 0;
  int ms = 0; // sync completion time
  String? error;

  @override
  String toString() => error != null
      ? 'Sync failed: $error'
      : '$ms ms · /sync calls $syncCalls · retries $retries · '
          'conflicts $conflicts (merged $merged, unresolved $unresolved) · '
          'pushed $pushed · pulled $pulled';
}

/// One sync cycle (lecture slide 22): push the outbox, then pull since the cursor.
class SyncEngine {
  SyncEngine(this.db, this.api, this.mode);

  final LocalDb db;
  final Api api;
  String mode; // 'lww' or 'version', set by Reset run
  bool online = true;
  bool _running = false;

  Future<SyncReport> syncNow() async {
    final report = SyncReport();
    if (!online) return report..error = 'offline';
    if (_running) return report..error = 'a sync is already running';
    _running = true;
    api.syncCalls = 0;
    api.retries = 0;
    final sw = Stopwatch()..start();
    try {
      // 1. PUSH the outbox, oldest first.
      //    Each op is re-read before it is sent, because an earlier push
      //    may have moved it onto a newer base version.
      final seqs = (await db.pendingOps()).map((o) => o.seq).toList();
      for (final seq in seqs) {
        final op = await db.opBySeq(seq);
        if (op == null) continue;
        final local = await db.task(op.taskId);
        if (local == null) continue;
        final reply = await api.push(op, mode, local);
        if (reply.status == 200) {
          await _accepted(op, reply.task);
          report.pushed++;
        } else {
          report.conflicts++;
          await resolveConflict(op, reply.task, report);
        }
      }

      // 2. PULL everything after our cursor, then save the new cursor.
      final since = await db.cursor() ?? 0;
      final (changed, cursor) = await api.changes(since);
      for (final t in changed) {
        await db.applyServerTask(t);
      }
      await db.setCursor(cursor);
      report.pulled = changed.length;
    } catch (e) {
      report.error = '$e';
    } finally {
      sw.stop();
      report.ms = sw.elapsedMilliseconds;
      report.syncCalls = api.syncCalls;
      report.retries = api.retries;
      _running = false;
    }
    return report;
  }

  /// The server accepted [sent] (200) and returned [result].
  Future<void> _accepted(OutboxOp sent, Task result) async {
    // Version N+1 is exactly our change: later edits of this task move onto it.
    final ours = mode == 'version' && result.version == sent.baseVersion + 1;
    // Delete the op (only after the server said OK) and rebase its followers
    // in one transaction.
    await db.completeOp(sent, rebaseTo: ours ? result.version : null);
    // If the app dies before this line, the next pull brings the same record.
    await db.applyServerTask(result);
  }

  /// Called when the server answers 409: [server] is its current copy.
  Future<void> resolveConflict(
      OutboxOp op, Task server, SyncReport report) async {
    // TODO 2: field-level merge (about 15 lines). See lecture slides 28-30.
    // 1. sameField = did the server change any field this op also changed?
    //    For each f in op.fields.keys, compare server.field(f) with op.baseFields[f].
    // 2. If op.op != 'update' or sameField: a merge would lose an edit.
    //    Call db.blockOp(op), add 1 to report.unresolved, and return.
    // 3. Otherwise the edits are independent:
    //      final rebased = await db.rebaseOp(op, server.version);
    //      final local = await db.task(op.taskId);
    //      final reply = await api.push(rebased, mode, local!);
    //    On 200: await _accepted(rebased, reply.task), then report.merged++.
    //    Otherwise: db.blockOp(rebased), report.unresolved++.
    // 1. Did the server change any field that this op also changed?
    final sameField = op.fields.keys
        .any((f) => server.field(f) != op.baseFields[f]);

    // 2. Same field (or not an update): merging would lose an edit, so ask the user.
    if (op.op != 'update' || sameField) {
      await db.blockOp(op);
      report.unresolved++;
      return;
    }

    // 3. Independent fields: rebase onto the server version and push again.
    final rebased = await db.rebaseOp(op, server.version);
    final local = await db.task(op.taskId);
    final reply = await api.push(rebased, mode, local!);
    if (reply.status == 200) {
      await _accepted(rebased, reply.task);
      report.merged++;
    } else {
      await db.blockOp(rebased);
      report.unresolved++;
    }
  }
}
