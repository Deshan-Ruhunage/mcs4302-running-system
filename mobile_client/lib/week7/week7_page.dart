import 'package:flutter/material.dart';

import 'api.dart';
import 'config.dart';
import 'local_db.dart';
import 'sync_engine.dart';
import 'task.dart';

/// Phone A. Every control the lab needs is on this one screen.
class Week7Page extends StatefulWidget {
  const Week7Page({super.key});

  @override
  State<Week7Page> createState() => _Week7PageState();
}

class _Week7PageState extends State<Week7Page> {
  final Api api = Api();
  LocalDb? db;
  SyncEngine? engine;

  List<Task> tasks = [];
  int outbox = 0;
  bool online = true;
  bool busy = false;
  SyncReport? lastSync;
  String? trafficLine;
  String? message;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final d = await LocalDb.open();
      db = d;
      online = await d.online();
      String mode = 'version';
      try {
        mode = await api.mode();
      } catch (_) {
        message = 'Backend not reachable; working offline.';
      }
      engine = SyncEngine(d, api, mode)..online = online;
      if (await d.cursor() == null && online) await _download();
      await _refresh();
      // Sync trigger: app start (lecture slide 20).
      if (online && outbox > 0) await _sync();
    } catch (e) {
      setState(() => message = 'Start-up failed: $e');
    }
  }

  Future<void> _download() async {
    final (all, cursor) = await api.allTasks();
    await db!.replaceAll(all, cursor);
  }

  Future<void> _refresh() async {
    final t = await db!.tasks();
    final n = await db!.outboxCount();
    if (!mounted) return;
    setState(() {
      tasks = t;
      outbox = n;
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (e) {
      message = '$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ------------------------------------------------------------ actions

  Future<void> _resetRun(String mode) => _guard(() async {
        await api.reset(mode);
        engine!.mode = mode;
        await _setOnlineFlag(true);
        await _download();
        lastSync = null;
        trafficLine = null;
        message = 'Reset: mode $mode, task-42 at v3, outbox empty.';
        await _refresh();
      });

  Future<void> _setOnlineFlag(bool v) async {
    online = v;
    engine!.online = v;
    await db!.setOnline(v);
  }

  Future<void> _toggleOnline(bool v) async {
    await _setOnlineFlag(v);
    setState(() {});
    // Sync trigger: back online.
    if (v) await _sync();
  }

  Future<void> _sync() => _guard(_doSync);

  Future<void> _doSync() async {
    lastSync = await engine!.syncNow();
    await _refresh();
    if (online) await _loadTraffic();
  }

  Future<void> _loadTraffic() async {
    final s = await api.stats();
    int bytes(String path) {
      final e = s['/w7$path'] as Map<String, dynamic>?;
      if (e == null) return 0;
      return (e['req_bytes'] as int) + (e['resp_bytes'] as int);
    }

    int last(String path) {
      final e = s['/w7$path'] as Map<String, dynamic>?;
      return e == null ? 0 : e['last_resp_bytes'] as int;
    }

    trafficLine = 'Sync traffic since reset: ${bytes('/sync') + bytes('/changes')} B '
        '(/sync ${bytes('/sync')} B, /changes ${bytes('/changes')} B) · '
        'last /changes reply ${last('/changes')} B · full /tasks reply ${last('/tasks')} B';
  }

  Future<void> _edit(Task t, Map<String, String> fields) async {
    await db!.editTask(t.id, fields);
    await _refresh();
    // Offline-first: the edit is already saved; sync only if we can.
    if (online) await _doSync();
  }

  Future<void> _phoneB(String field, String value) => _guard(() async {
        await api.phoneBEdit(field, value);
        message = 'Phone B set $field → "$value" (its clock is 10 min fast).';
      });

  Future<void> _showServerCopy() => _guard(() async {
        final s = await api.serverTask('task-42');
        message = 'Server task-42: "${s.title}", ${s.status}, v${s.version}';
      });

  Future<void> _editDialog(Task t) async {
    final title = TextEditingController(text: t.title);
    var status = t.status;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Edit ${t.id}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Title')),
            DropdownButton<String>(
              value: status,
              items: const ['open', 'closed']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setD(() => status = v ?? status),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                // Only the fields that actually changed go in the outbox.
                final f = <String, String>{};
                if (title.text != t.title) f['title'] = title.text;
                if (status != t.status) f['status'] = status;
                Navigator.pop(ctx, f);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result != null && result.isNotEmpty) {
      await _guard(() => _edit(t, result));
    }
  }

  // ------------------------------------------------------------ UI

  Color _stateColor(String s) => switch (s) {
        'pending' => Colors.orange,
        'conflict' => Colors.red,
        _ => Colors.green,
      };

  Widget _taskTile(Task t) => ListTile(
        dense: true,
        title: Text(t.title),
        subtitle: Text('${t.id} · ${t.status} · v${t.version}'
            '${t.isDirty ? ' · dirty' : ''}'),
        trailing: Chip(
          label: Text(t.syncState),
          backgroundColor: _stateColor(t.syncState).withOpacity(0.15),
        ),
        onTap: () => _editDialog(t),
        onLongPress: () => _guard(() async {
          await db!.deleteTask(t.id); // tombstone + outbox (worked example)
          await _refresh();
          if (online) await _doSync();
        }),
      );

  @override
  Widget build(BuildContext context) {
    final t42 = tasks.where((t) => t.id == 'task-42').firstOrNull;
    final others = tasks.where((t) => t.id != 'task-42').take(30).toList();
    final mode = engine?.mode ?? '…';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Week 7 · Phone A'),
        actions: [
          Text(online ? 'Online' : 'Offline'),
          Switch(value: online, onChanged: busy || engine == null ? null : _toggleOnline),
        ],
      ),
      body: db == null
          ? Center(child: Text(message ?? 'Opening database…'))
          : ListView(padding: const EdgeInsets.all(12), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Run controls · server mode: $mode · outbox: $outbox',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton(
                          onPressed: busy ? null : () => _resetRun('lww'),
                          child: const Text('Reset run: LWW')),
                      OutlinedButton(
                          onPressed: busy ? null : () => _resetRun('version'),
                          child: const Text('Reset run: Version')),
                      FilledButton.tonal(
                          onPressed: busy ? null : () => _phoneB('status', kStatusB),
                          child: const Text('Phone B: status → closed')),
                      FilledButton.tonal(
                          onPressed: busy ? null : () => _phoneB('title', kTitleB),
                          child: const Text('Phone B: title → parts ordered')),
                      OutlinedButton(
                          onPressed: busy ? null : () => _guard(api.dropNextReply),
                          child: const Text('Drop next reply')),
                      OutlinedButton(
                          onPressed: busy ? null : _showServerCopy,
                          child: const Text('Server copy of 42')),
                      FilledButton(
                          onPressed: busy || !online ? null : _sync,
                          child: const Text('Sync now')),
                    ]),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Part 3: new idempotency key on each retry'),
                      value: api.newKeyOnRetry,
                      onChanged: (v) => setState(() => api.newKeyOnRetry = v),
                    ),
                  ]),
                ),
              ),
              if (message != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(message!)),
              if (lastSync != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Last sync: $lastSync'
                        '${trafficLine != null ? '\n$trafficLine' : ''}'),
                  ),
                ),
              if (t42 != null)
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Column(children: [
                    _taskTile(t42),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FilledButton(
                        onPressed: busy ? null : () => _guard(() => _edit(t42, {'title': kTitleA})),
                        child: const Text('Phone A: title → urgent'),
                      ),
                    ),
                  ]),
                ),
              const Divider(),
              Text('Other tasks (first 30 of ${tasks.length - 1}; tap to edit, long-press to delete)'),
              ...others.map(_taskTile),
            ]),
    );
  }
}
