import 'package:flutter/material.dart';

import 'frame_counter.dart';
import 'item.dart';
import 'item_repository.dart';

class RunResult {
  const RunResult({
    required this.useIsolate,
    required this.n,
    required this.endToEndMs,
    required this.fetchMs,
    required this.decodeMs,
    required this.stats,
  });

  final bool useIsolate;
  final int n;
  final int endToEndMs;
  final int fetchMs;
  final int decodeMs;
  final FrameStats stats;

  String get mode => useIsolate ? 'isolate' : 'ui';

  String get window => stats.decodeWindow ? 'decode' : 'whole-run';

  String toCsv() => 'W6RUN,$mode,$n,$endToEndMs,$fetchMs,$decodeMs,'
      '${stats.worstMs.toStringAsFixed(1)},${stats.estDropped},'
      '${stats.frames},$window';
}

/// Part 3: fetch /w6/bulk, decode on the UI isolate or with Isolate.run,
/// and record timing and dropped frames. The spinning icon keeps frames
/// coming, so a blocked UI isolate shows up as dropped frames.
class PerfPage extends StatefulWidget {
  const PerfPage({super.key, required this.api});

  final ApiItemRepository api;

  @override
  State<PerfPage> createState() => _PerfPageState();
}

class _PerfPageState extends State<PerfPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();
  final _frames = FrameCounter();
  final _results = <RunResult>[];

  int _n = 5000;
  bool _useIsolate = false;
  bool _running = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _frames.attach();
  }

  @override
  void dispose() {
    _frames.detach();
    _spin.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    _frames.start();
    try {
      final total = Stopwatch()..start();
      final body = await widget.api.fetchBulkBody(_n); // waiting: free
      final fetchMs = total.elapsedMilliseconds;

      final decodeStartUs = FrameCounter.nowUs();
      final decode = Stopwatch()..start();
      final items = _useIsolate
          ? await decodeItemsInIsolate(body) // computing, on a worker
          : decodeItems(body); // computing, on the UI isolate
      final decodeMs = decode.elapsedMilliseconds;
      final endToEndMs = total.elapsedMilliseconds;
      final decodeEndUs = FrameCounter.nowUs();

      // Profile mode reports frame timings in ~1 s batches: let them arrive.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final r = RunResult(
        useIsolate: _useIsolate,
        n: items.length,
        endToEndMs: endToEndMs,
        fetchMs: fetchMs,
        decodeMs: decodeMs,
        stats: _frames.stop(fromUs: decodeStartUs, toUs: decodeEndUs),
      );
      debugPrint(r.toCsv());
      if (!mounted) return;
      setState(() => _results.insert(0, r));
    } catch (e) {
      _frames.stop(fromUs: 0, toUs: 0);
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear results',
            onPressed: _running ? null : () => setState(_results.clear),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: RotationTransition(
              turns: _spin,
              child: const Icon(Icons.autorenew, size: 72),
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 5000, label: Text('n = 5k')),
              ButtonSegment(value: 50000, label: Text('n = 50k')),
            ],
            selected: {_n},
            onSelectionChanged:
                _running ? null : (s) => setState(() => _n = s.first),
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('UI isolate')),
              ButtonSegment(value: true, label: Text('Isolate.run')),
            ],
            selected: {_useIsolate},
            onSelectionChanged:
                _running ? null : (s) => setState(() => _useIsolate = s.first),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _running ? null : _run,
            child: Text(_running ? 'Running...' : 'Run'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 16),
          for (final r in _results)
            Card(
              child: ListTile(
                dense: true,
                title: Text('${r.mode}  n=${r.n}'),
                subtitle: Text(
                  'end-to-end ${r.endToEndMs} ms  (fetch ${r.fetchMs}, '
                  'decode ${r.decodeMs})\n'
                  'worst frame ${r.stats.worstMs.toStringAsFixed(1)} ms  '
                  'est. dropped ${r.stats.estDropped}  '
                  '(${r.stats.frames} frames, ${r.window} window)',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
