import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/api_client.dart';
import 'background_jobs.dart';
import 'notifications.dart';

/// Week 5 Part 4: schedule one background job per condition and read back
/// when it actually ran (server clock).
class JobsScreen extends StatefulWidget {
  final ApiClient api;
  const JobsScreen({super.key, required this.api});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  static const delay = Duration(seconds: 60);

  static const conditions = {
    'J1': 'Normal. Schedule, then press Home. Usually starts within a few '
        'minutes; if it takes longer, note it and investigate.',
    'J2': 'Doze. Schedule, press Home, run doze_on within 60 s. '
        'At about 3 minutes after scheduling, run doze_step until the state '
        'is IDLE_MAINTENANCE.',
    'J3': 'Rare bucket. Schedule, press Home, run bucket_rare within 60 s. '
        'Watch for 5 minutes.',
    'J4': 'Restricted bucket. Schedule, press Home, run bucket_restricted '
        'within 60 s. Watch for 5 minutes.',
  };

  String _label = 'J1';
  List<Map<String, dynamic>> _rows = [];
  bool _busy = false;
  String _status = 'Run reset_all before each condition.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _status = 'Error: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _schedule() => _guard(() async {
        final allowed = await Notifications.isEnabled();
        final id = await BackgroundJobs.scheduleSync(widget.api, _label,
            delay: delay);
        final now = DateTime.now();
        final t = '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}:'
            '${now.second.toString().padLeft(2, '0')}';
        _status = 'Scheduled $id at $t. Press Home now.'
            '${allowed ? '' : ' (Notifications are off: the job will run, '
                'but you will not see a notification.)'}';
      });

  Future<void> _refresh() => _guard(() async {
        _rows = await widget.api.getJobSummary();
        _status = 'Results updated (${_rows.length} jobs).';
      });

  Future<void> _clear() => _guard(() async {
        await BackgroundJobs.cancelAll();
        await widget.api.clearJobLog();
        _rows = [];
        _status = 'Pending jobs cancelled and job log cleared.';
      });

  Future<void> _copyCsv() async {
    const cols = [
      'label', 'job_id', 'requested_delay_s', 'scheduled_at', 'started_at',
      'ran_at', 'extra_delay_s', 'work_s', 'status', 'runs'
    ];
    final lines = [
      cols.join(','),
      for (final r in _rows) cols.map((c) => '${r[c] ?? ''}').join(','),
    ];
    final csv = lines.join('\n');
    debugPrint(csv);
    await Clipboard.setData(ClipboardData(text: csv));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV copied (also printed in the terminal)')));
    }
  }

  String _fmt(dynamic v) => v == null ? '-' : '$v';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Background jobs')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: [
              for (final c in conditions.keys)
                ButtonSegment(value: c, label: Text(c)),
            ],
            selected: {_label},
            onSelectionChanged: _busy
                ? null
                : (s) => setState(() => _label = s.first),
          ),
          const SizedBox(height: 12),
          Text(conditions[_label]!),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _schedule,
            icon: const Icon(Icons.schedule),
            label: Text('Schedule $_label (minimum delay ${delay.inSeconds} s)'),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('Refresh results')),
            OutlinedButton(
                onPressed: _rows.isEmpty ? null : _copyCsv,
                child: const Text('Copy CSV')),
            OutlinedButton(
                onPressed: _busy ? null : _clear,
                child: const Text('Clear log')),
          ]),
          const SizedBox(height: 12),
          Text(_status, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Job')),
                DataColumn(label: Text('Scheduled')),
                DataColumn(label: Text('Started')),
                DataColumn(label: Text('Finished')),
                DataColumn(label: Text('Extra s'), numeric: true),
                DataColumn(label: Text('Work s'), numeric: true),
                DataColumn(label: Text('Waiting s'), numeric: true),
                DataColumn(label: Text('Status')),
              ],
              rows: [
                for (final r in _rows)
                  DataRow(cells: [
                    DataCell(Text(_fmt(r['label']))),
                    DataCell(Text(_fmt(r['scheduled_at']))),
                    DataCell(Text(_fmt(r['started_at']))),
                    DataCell(Text(_fmt(r['ran_at']))),
                    DataCell(Text(_fmt(r['extra_delay_s']))),
                    DataCell(Text(_fmt(r['work_s']))),
                    DataCell(Text(_fmt(r['waiting_s']))),
                    DataCell(Text(_fmt(r['status']))),
                  ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
