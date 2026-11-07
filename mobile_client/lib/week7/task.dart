import 'dart:convert';

/// One task (record). The same shape is used on the server and in SQLite.
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.status,
    required this.version,
    required this.updatedAt,
    this.isDirty = false,
    this.isDeleted = false,
    this.syncState = 'synced',
  });

  final String id;
  final String title;
  final String status;

  /// Last version the SERVER acknowledged. The phone never invents versions.
  final int version;
  final String updatedAt;
  final bool isDirty;
  final bool isDeleted;

  /// 'synced', 'pending' or 'conflict' (shown in the UI).
  final String syncState;

  /// Value of a synced field by name ('title' or 'status').
  String field(String name) => name == 'title' ? title : status;

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        title: j['title'] as String,
        status: j['status'] as String,
        version: j['version'] as int,
        updatedAt: j['updated_at'] as String,
        isDeleted: j['is_deleted'] as bool? ?? false,
      );

  factory Task.fromDb(Map<String, Object?> r) => Task(
        id: r['id'] as String,
        title: r['title'] as String,
        status: r['status'] as String,
        version: r['version'] as int,
        updatedAt: r['updated_at'] as String,
        isDirty: (r['is_dirty'] as int) == 1,
        isDeleted: (r['is_deleted'] as int) == 1,
        syncState: r['sync_state'] as String,
      );

  /// Row for a task that came from the server (so it is clean).
  Map<String, Object?> toDb() => {
        'id': id,
        'title': title,
        'status': status,
        'version': version,
        'updated_at': updatedAt,
        'is_dirty': 0,
        'is_deleted': isDeleted ? 1 : 0,
        'sync_state': 'synced',
      };
}

/// One queued operation in the outbox table.
class OutboxOp {
  const OutboxOp({
    required this.seq,
    required this.taskId,
    required this.op,
    required this.fields,
    required this.baseFields,
    required this.baseVersion,
    required this.updatedAt,
    required this.idemKey,
  });

  final int seq; // order of the edits (oldest first)
  final String taskId;
  final String op; // 'update' or 'delete'
  final Map<String, String> fields; // the changed fields, new values
  final Map<String, String> baseFields; // the same fields, values BEFORE the edit
  final int baseVersion; // server version the edit was based on
  final String updatedAt; // device time of the edit (only LWW uses it)
  final String idemKey;

  factory OutboxOp.fromDb(Map<String, Object?> r) => OutboxOp(
        seq: r['seq'] as int,
        taskId: r['task_id'] as String,
        op: r['op'] as String,
        fields: Map<String, String>.from(jsonDecode(r['fields'] as String) as Map),
        baseFields:
            Map<String, String>.from(jsonDecode(r['base_fields'] as String) as Map),
        baseVersion: r['base_version'] as int,
        updatedAt: r['updated_at'] as String,
        idemKey: r['idem_key'] as String,
      );
}
