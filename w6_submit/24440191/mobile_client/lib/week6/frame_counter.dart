import 'dart:developer' show Timeline;
import 'dart:math';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart';

class FrameStats {
  const FrameStats({
    required this.frames,
    required this.estDropped,
    required this.worstMs,
    required this.decodeWindow,
  });

  /// Frames used for the stats.
  final int frames;

  /// Estimated frames missed: a frame that cost 3 budgets counts as 2.
  final int estDropped;

  /// Slowest frame (ms), from vsync to the end of the slower thread.
  final double worstMs;

  /// True: only frames overlapping the decode window were used.
  /// False: the window matched no frames, so the whole run was used.
  final bool decodeWindow;
}

/// Collects the engine's FrameTiming reports and summarises the frames that
/// overlap a measurement window (the decode, plus two frame budgets either
/// side so a short decode still catches the frame it delayed).
///
/// A frame's cost is max(vsync wait + build, raster). When the UI isolate is
/// blocked, the next frame starts late even though its build is fast, so the
/// delay shows up as vsync wait.
///
/// In profile/release mode the engine reports timings in batches about once
/// per second, so wait ~1.5 s after the window before calling [stop].
class FrameCounter {
  FrameCounter({this.budgetMs = 1000 / 60});

  final double budgetMs;
  final List<FrameTiming> _timings = [];
  bool _recording = false;

  /// Timestamp in the same monotonic clock as FrameTiming (microseconds).
  static int nowUs() => Timeline.now;

  void attach() => SchedulerBinding.instance.addTimingsCallback(_onTimings);
  void detach() => SchedulerBinding.instance.removeTimingsCallback(_onTimings);

  void start() {
    _timings.clear();
    _recording = true;
  }

  FrameStats stop({required int fromUs, required int toUs}) {
    _recording = false;
    final marginUs = (2 * budgetMs * 1000).round();
    final inWindow = [
      for (final t in _timings)
        if (t.timestampInMicroseconds(FramePhase.vsyncStart) <=
                toUs + marginUs &&
            t.timestampInMicroseconds(FramePhase.rasterFinish) >=
                fromUs - marginUs)
          t,
    ];
    // If no frame matches, the clocks may differ on this platform:
    // fall back to every frame in the run and say so.
    final windowed = inWindow.isNotEmpty;
    final used = windowed ? inWindow : _timings;

    var estDropped = 0;
    var worst = 0.0;
    for (final t in used) {
      final c = _costMs(t);
      estDropped += max(0, (c / budgetMs).ceil() - 1);
      worst = max(worst, c);
    }
    return FrameStats(
      frames: used.length,
      estDropped: estDropped,
      worstMs: worst,
      decodeWindow: windowed,
    );
  }

  double _costMs(FrameTiming t) {
    final ui = t.vsyncOverhead + t.buildDuration;
    final cost = ui > t.rasterDuration ? ui : t.rasterDuration;
    return cost.inMicroseconds / 1000;
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_recording) _timings.addAll(timings);
  }
}
