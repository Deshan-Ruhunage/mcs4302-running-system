import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'api/api_client.dart';
import 'notifications.dart';

/// Task name passed to WorkManager. Every job in this lab runs the same task.
const syncTaskName = 'mcs4302.sync';

/// Entry point that Android starts when a job is due.
///
/// It may run in a NEW isolate (or a new process, if Android killed the app),
/// so it must not rely on anything the UI created: it builds its own ApiClient
/// and initialises notifications itself. The pragma stops the compiler from
/// removing it, because nothing in the app calls it directly.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    final jobId = inputData?['job_id'] as String? ?? 'unknown';
    final label = inputData?['label'] as String? ?? '?';
    debugPrint('[JOB] $jobId started on the device at ${DateTime.now()}');

    final api = ApiClient();
    try {
      // 1. TODO 4a: record that Android STARTED the worker, before any real
      //    work, by sending a 'started' event with api.logJob(...). Wrap it in
      //    its own try/catch: a failed log must not stop the job.
      //    Why log it BEFORE the fetch below, and not after?
      try {
        await api.logJob(jobId: jobId, label: label, event: 'started');
      } catch (e) {
        debugPrint('[JOB] $jobId started-log failed: $e');
      }
      // 2. The actual work: fetch from the backend.
      final items = await api.getItems();
      // 3. Record that the work FINISHED, using the server clock.
      await api.logJob(
          jobId: jobId, label: label, event: 'ran', detail: 'items=${items.length}');
      // 4. Tell the user. A failed notification must not fail the job.
      try {
        await Notifications.show(
          id: jobId.hashCode & 0x7fffffff,
          title: 'Items synced ($label)',
          body: '${items.length} items on the server',
        );
      } catch (e) {
        debugPrint('[JOB] $jobId notification failed: $e');
      }
      debugPrint('[JOB] $jobId finished');
      // TODO 4b: what should the worker return after SUCCESS, and why?
      //          (true = success; false = failure, so WorkManager retries.)
      return true; // success: the work is done, so WorkManager must not run it again
    } catch (e) {
      debugPrint('[JOB] $jobId failed: $e');
      // TODO 4b: what should the worker return after a FAILURE, and why?
      //          What would happen to your measurements with each choice?
      // WARNING: this placeholder reports a FAILED job as a success.
      //          Review it before you collect any measurements.
      return false; // failure: ask WorkManager to retry later instead of hiding the error as success
    } finally {
      api.close();
    }
  });
}

class BackgroundJobs {
  BackgroundJobs._();

  /// Call once in main(), before runApp().
  static Future<void> init() => Workmanager().initialize(callbackDispatcher);

  /// Asks Android to run one sync job no earlier than [delay] from now, when
  /// a network is available. [delay] is a MINIMUM, not a deadline: WorkManager
  /// runs deferrable work, and Doze and App Standby can postpone it further.
  static Future<String> scheduleSync(
    ApiClient api,
    String label, {
    Duration delay = const Duration(seconds: 60),
  }) async {
    final jobId = '$label-${DateTime.now().millisecondsSinceEpoch}';
    // 1. Register with Android FIRST. If this throws, nothing is logged, so
    //    the backend never shows a job that does not exist.
    await Workmanager().registerOneOffTask(
      jobId, // unique name
      syncTaskName,
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.connected),
      inputData: {'job_id': jobId, 'label': label},
    );
    // 2. Then record the scheduling time on the server. The job cannot start
    //    before its minimum delay, so this log always arrives first. If the
    //    log fails, cancel the job so the two stay consistent.
    try {
      await api.logJob(
        jobId: jobId,
        label: label,
        event: 'scheduled',
        requestedDelaySeconds: delay.inSeconds.toDouble(),
      );
    } catch (e) {
      await Workmanager().cancelByUniqueName(jobId);
      rethrow;
    }
    debugPrint('[JOB] $jobId scheduled, minimum delay ${delay.inSeconds} s');
    return jobId;
  }

  static Future<void> cancelAll() => Workmanager().cancelAll();
}
