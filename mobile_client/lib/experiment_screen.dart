import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/api_client.dart';
import 'api/retry.dart';
import 'experiment.dart';

class ExperimentScreen extends StatefulWidget {
  final ApiClient api;
  const ExperimentScreen({super.key, required this.api});

  @override
  State<ExperimentScreen> createState() => _ExperimentScreenState();
}

class _ExperimentScreenState extends State<ExperimentScreen> {
  final results = <ExperimentResult>[];
  bool running = false;
  static int nextSeed = 42;
  String status = 'Ready';

  static const conditions = [
    ('A: fail 0.3, no retry', 0.3, RetryPolicy.none),
    ('B: fail 0.3, retry', 0.3, RetryPolicy()),
    ('C: fail 0.6, no retry', 0.6, RetryPolicy.none),
    ('D: fail 0.6, retry', 0.6, RetryPolicy()),
  ];

  Future<void> _run() async {
    setState(() {
      running = true;
      results.clear();
    });
    final seed = nextSeed;
    try {
      for (final (label, failRate, policy) in conditions) {
        if (!mounted) return;
        setState(() => status = 'Seed $seed: running $label ...');
        final r = await runExperiment(widget.api,
            label: label, failRate: failRate, policy: policy, seed: seed);
        if (!mounted) return;
        setState(() => results.add(r));
      }
      if (mounted) setState(() { status = 'Done (seed $seed)'; nextSeed++; });
    } catch (e) {
      if (mounted) setState(() => status = 'Stopped: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  String get _csv => 'condition,seed,n,success_pct,mean_ms,p95_ms,http_calls\n'
      '${results.map((r) => r.toCsv()).join('\n')}';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !running,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Retry experiment'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy CSV',
            onPressed: running || results.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _csv));
                    debugPrint(_csv);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('CSV copied and printed to console')));
                  },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: running ? null : _run,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run experiment (4 x 50 requests)'),
            ),
            const SizedBox(height: 8),
            Text(status),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Condition')),
                  DataColumn(label: Text('Success %'), numeric: true),
                  DataColumn(label: Text('Mean ms'), numeric: true),
                  DataColumn(label: Text('p95 ms'), numeric: true),
                  DataColumn(label: Text('HTTP calls'), numeric: true),
                ],
                rows: [
                  for (final r in results)
                    DataRow(cells: [
                      DataCell(Text(r.label)),
                      DataCell(Text(r.successRate.toStringAsFixed(1))),
                      DataCell(Text(r.meanMs.toStringAsFixed(0))),
                      DataCell(Text(r.p95Ms.toStringAsFixed(0))),
                      DataCell(Text('${r.httpCalls}')),
                    ]),
                ],
              ),
            ),
          ],
        )),
      ),
      ),
    );
  }
}
