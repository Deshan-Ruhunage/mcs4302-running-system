import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'task.dart';

/// The phone's database. The UI reads and writes ONLY here (offline-first).
class LocalDb {
  LocalDb._(this.db);

  final Database db;
  static const _uuid = Uuid();

  static Future<LocalDb> open() async {
    final path = p.join(await getDatabasesPath(), 'week7.db');
    final db = await openDatabase(path, version: 1, onCreate: (db, v) async {
      // The sync columns from lecture slide 13.
      await db.execute('''
        CREATE TABLE task(
          id          TEXT PRIMARY KEY,
          title       TEXT NOT NULL,
          status      TEXT NOT NULL,
          version     INTEGER NOT NULL,
          updated_at  TEXT NOT NULL,
          is_dirty    INTEGER NOT NULL DEFAULT 0,
          is_deleted  INTEGER NOT NULL DEFAULT 0,
          sync_state  TEXT NOT NULL DEFAULT 'synced')''');
      // The outbox from lecture slide 19.
      await db.execute('''
        CREATE TABLE outbox(
          seq           INTEGER PRIMARY KEY AUTOINCREMENT,
          task_id       TEXT NOT NULL,
          op            TEXT NOT NULL,
          fields        TEXT NOT NULL,
          base_fields   TEXT NOT NULL,
          base_version  INTEGER NOT NULL,
          updated_at    TEXT NOT NULL,
          idem_key      TEXT NOT NULL,
          blocked       INTEGER NOT NULL DEFAULT 0)''');
      // Key-value: the sync cursor and the offline switch.
      await db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
    });
    return LocalDb._(db);
  }

  // ------------------------------------------------------------ reads (UI)

  Future<List<Task>> tasks() async {
    final rows = await db.query('task',
        where: 'is_deleted = 0',
        orderBy: "CASE WHEN id = 'task-42' THEN 0 ELSE 1 END, id");
    return rows.map(Task.fromDb).toList();
  }

  Future<Task?> task(String id) async {
    final rows = await db.query('task', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Task.fromDb(rows.first);
  }

  // ------------------------------------------------------------ local writes

  /// WORKED EXAMPLE: a delete is a tombstone plus an outbox entry,
  /// written in ONE transaction. Use it as the pattern for TODO 1.
  Future<void> deleteTask(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query('task', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final current = Task.fromDb(rows.first);

      // 1. Change the task row: tombstone, not a real DELETE, so the delete can sync.
      await txn.update(
        'task',
        {'is_deleted': 1, 'is_dirty': 1, 'updated_at': now, 'sync_state': 'pending'},
        where: 'id = ?',
        whereArgs: [id],
      );

      // 2. Queue the operation, with a fresh idempotency key.
      await txn.insert('outbox', {
        'task_id': id,
        'op': 'delete',
        'fields': jsonEncode(<String, String>{}),
        'base_fields': jsonEncode(<String, String>{}),
        'base_version': current.version,
        'updated_at': now,
        'idem_key': _uuid.v4(),
      });
    });
  }

  /// Edit some fields of a task, e.g. {'title': 'Pump repair – urgent'}.
  Future<void> editTask(String id, Map<String, String> fields) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query('task', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final current = Task.fromDb(rows.first);

      // TODO 1: follow the pattern of deleteTask above (about 15 lines).
      // 1. Update the task row with the new values in `fields`.
      //    Also set is_dirty = 1, updated_at = now, sync_state = 'pending'.
      //    Do NOT change `version`: only the server issues versions.
      // 2. Insert ONE outbox row with these columns:
      //      task_id, op ('update'), fields (jsonEncode(fields)),
      //      base_fields: the SAME keys with their values BEFORE the edit,
      //        e.g. jsonEncode({for (final k in fields.keys) k: current.field(k)}),
      //      base_version (current.version), updated_at (now), idem_key (_uuid.v4()).
      // Both writes use `txn`, so they succeed or fail together.
      // 1. Change the task row (version is NOT changed: only the server issues versions).
      await txn.update(
        'task',
        {...fields, 'is_dirty': 1, 'updated_at': now, 'sync_state': 'pending'},
        where: 'id = ?',
        whereArgs: [id],
      );

      // 2. Queue the operation in the SAME transaction, with a fresh idempotency key.
      await txn.insert('outbox', {
        'task_id': id,
        'op': 'update',
        'fields': jsonEncode(fields),
        'base_fields': jsonEncode({for (final k in fields.keys) k: current.field(k)}),
        'base_version': current.version,
        'updated_at': now,
        'idem_key': _uuid.v4(),
      });
    });
  }

  // ------------------------------------------------------------ outbox (sync engine)

  /// Unsent, unblocked operations, oldest first.
  Future<List<OutboxOp>> pendingOps() async {
    final rows =
        await db.query('outbox', where: 'blocked = 0', orderBy: 'seq ASC');
    return rows.map(OutboxOp.fromDb).toList();
  }

  Future<int> outboxCount() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  /// Delete an outbox row. Call this only AFTER the server replied OK.
  Future<void> removeOp(int seq) =>
      db.delete('outbox', where: 'seq = ?', whereArgs: [seq]);

  /// One queued op by its seq, or null if it was removed or blocked meanwhile.
  Future<OutboxOp?> opBySeq(int seq) async {
    final rows = await db.query('outbox',
        where: 'seq = ? AND blocked = 0', whereArgs: [seq]);
    return rows.isEmpty ? null : OutboxOp.fromDb(rows.first);
  }

  /// The server accepted [sent]. In ONE transaction: delete it from the outbox
  /// and, if [rebaseTo] is given, move later queued edits of the same task
  /// (based on the same old version) onto that version. A crash can then never
  /// leave the op deleted but its followers on an outdated base version.
  Future<void> completeOp(OutboxOp sent, {int? rebaseTo}) async {
    await db.transaction((txn) async {
      await txn.delete('outbox', where: 'seq = ?', whereArgs: [sent.seq]);
      if (rebaseTo != null) {
        await txn.update('outbox', {'base_version': rebaseTo},
            where: 'task_id = ? AND base_version = ? AND seq > ? AND blocked = 0',
            whereArgs: [sent.taskId, sent.baseVersion, sent.seq]);
      }
    });
  }

  /// Rebase a queued op on a newer server version (after a merge).
  /// It is saved before it is sent, with a new idempotency key, so a crash
  /// mid-sync still leaves a correct outbox.
  Future<OutboxOp> rebaseOp(OutboxOp op, int serverVersion) async {
    final key = _uuid.v4();
    await db.update('outbox', {'base_version': serverVersion, 'idem_key': key},
        where: 'seq = ?', whereArgs: [op.seq]);
    final rows =
        await db.query('outbox', where: 'seq = ?', whereArgs: [op.seq]);
    return OutboxOp.fromDb(rows.first);
  }

  /// Park an op that cannot be merged automatically and flag its task.
  Future<void> blockOp(OutboxOp op) async {
    await db.transaction((txn) async {
      await txn.update('outbox', {'blocked': 1},
          where: 'seq = ?', whereArgs: [op.seq]);
      await txn.update('task', {'sync_state': 'conflict'},
          where: 'id = ?', whereArgs: [op.taskId]);
    });
  }

  // ------------------------------------------------------------ server data

  /// Store a task that came from the server (push reply or pull).
  Future<void> applyServerTask(Task t) async {
    // Local edits still queued for this task: keep them, do not overwrite.
    final pending = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM outbox WHERE task_id = ?', [t.id])) ??
        0;
    if (pending > 0) return;
    // Monotonic reads: never go back to an older version.
    final local = await task(t.id);
    if (local != null && t.version < local.version) return;
    await db.insert('task', t.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// First run or "Reset run": full download replaces everything.
  Future<void> replaceAll(List<Task> tasks, int cursor) async {
    await db.transaction((txn) async {
      await txn.delete('task');
      await txn.delete('outbox');
      final batch = txn.batch();
      for (final t in tasks) {
        batch.insert('task', t.toDb());
      }
      await batch.commit(noResult: true);
      await txn.insert('meta', {'key': 'cursor', 'value': '$cursor'},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<int?> cursor() async => int.tryParse(await _meta('cursor') ?? '');
  Future<void> setCursor(int c) => _setMeta('cursor', '$c');

  Future<bool> online() async => (await _meta('online') ?? '1') == '1';
  Future<void> setOnline(bool v) => _setMeta('online', v ? '1' : '0');

  Future<String?> _meta(String key) async {
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _setMeta(String key, String value) => db.insert(
      'meta', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);
}
