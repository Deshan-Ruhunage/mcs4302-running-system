import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around flutter_local_notifications (Android only in this lab).
/// Safe to call from the UI and from the background job: init() runs once
/// per isolate.
class Notifications {
  Notifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// True if the user currently allows notifications for this app.
  static Future<bool> isEnabled() async {
    await init();
    return await _android?.areNotificationsEnabled() ?? false;
  }

  /// Shows the system permission dialog (Android 13+) when Android allows it.
  /// If the user has refused too often, Android returns false WITHOUT
  /// showing anything.
  static Future<bool> request() async {
    await init();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  /// Opens this app's notification settings page.
  static Future<void> openSettings() async {
    await init();
    await _android?.openAppNotificationSettings();
  }

  static Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'sync',
          'Sync results',
          channelDescription: 'Results of background sync jobs',
        ),
      ),
    );
  }
}
