import 'package:flutter/material.dart';

/// In-memory log of lifecycle events, with timestamps.
///
/// It lives only as long as the PROCESS does. Part 2 uses this on purpose:
/// after Android kills the process, this log starts empty again.
class LifecycleLog {
  LifecycleLog._();

  static final ValueNotifier<List<String>> entries =
      ValueNotifier<List<String>>(const []);

  static void add(String what) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
    final line = '$stamp  $what';
    debugPrint('[LIFECYCLE] $line'); // visible in Logcat under the "flutter" tag
    entries.value = [...entries.value, line];
  }
}

/// Bottom sheet that shows the log, newest first, and updates live.
void showLifecycleLog(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => ValueListenableBuilder<List<String>>(
      valueListenable: LifecycleLog.entries,
      builder: (context, lines, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Lifecycle log (this process only)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final line in lines.reversed)
            Text(line, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
    ),
  );
}
