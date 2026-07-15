import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'vault.dart';
import 'wire_client.dart';

const String _fcmChannelId    = 'chick_sprint_alerts';
const String _fcmChannelName  = 'Chick Sprint alerts';
const String _fcmChannelDesc  = 'Notifications for offers and promos';
const String _notifSmallIcon  = '@drawable/ic_notification_flame';
const String _notifLargeIcon  = '@mipmap/ic_launcher';

/// Sanitises a candidate push URL. Rejects anything without http/https
/// scheme, authority, or that matches the AppsFlyer stub. This is the
/// mitigation for pitfalls §12 — the tempest screen was fired when
/// `deep_link_test` was fed to the WebView.
Uri? sanitisePushUri(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.toLowerCase() == 'deep_link_test') return null;
  final u = Uri.tryParse(trimmed);
  if (u == null) return null;
  if (u.scheme != 'http' && u.scheme != 'https') return null;
  if (!u.hasAuthority) return null;
  return u;
}

/// Extract a URL from a push payload by walking a list of aliases.
String? extractPushUrl(Map<String, dynamic> data) {
  const keys = <String>[
    'url',
    'link',
    'landing_page',
    'target_url',
    'deep_link_value',
  ];
  for (final k in keys) {
    final v = data[k];
    if (v is String) {
      final u = sanitisePushUri(v);
      if (u != null) return u.toString();
    }
  }
  return null;
}

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  // System is already displaying the notification. Nothing to do
  // from the background isolate — the tap is handled when the main
  // isolate comes back to the foreground.
}

/// PushHub — Firebase Messaging owner + local notification bridge.
class PushHub {
  PushHub(this._vault);

  final Vault _vault;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  FirebaseMessaging? _fcm;
  String? _token;
  bool _booted = false;

  /// Fired when the user taps a notification while the app is warm
  /// (either foregrounded or backgrounded). Do NOT persist the URL —
  /// consume it in-place.
  void Function(String url)? onWarmTap;

  /// Fired when FCM rotates the device token. Router re-POSTs the
  /// gateway with the new token.
  void Function(String newToken)? onTokenRotate;

  String? get token => _token;

  Future<void> boot() async {
    if (_booted) return;
    try {
      await Firebase.initializeApp();
      _fcm = FirebaseMessaging.instance;

      FirebaseMessaging.onBackgroundMessage(_bgHandler);

      await _prepareLocal();

      _token = await _fcm!.getToken();
      _fcm!.onTokenRefresh.listen((t) {
        _token = t;
        onTokenRotate?.call(t);
      });

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onWarmTap);

      final cold = await _fcm!.getInitialMessage();
      if (cold != null) await _onColdTap(cold);

      _booted = true;
    } catch (_) {
      // Firebase not configured — carry on without push.
    }
  }

  Future<void> _prepareLocal() async {
    const androidSettings =
        AndroidInitializationSettings(_notifSmallIcon);
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == null) return;
        try {
          final data = jsonDecode(response.payload!) as Map<String, dynamic>;
          final url = extractPushUrl(data);
          if (url != null) onWarmTap?.call(url);
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final androidPlugin = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _fcmChannelId,
          _fcmChannelName,
          description: _fcmChannelDesc,
          importance: Importance.high,
        ),
      );
    }
  }

  /// Show the system permission prompt. On Android <13 permission is
  /// implicit; the SDK returns `authorized` immediately. On Android
  /// 13+ the user may pick "deny" — we latch it in the vault so we
  /// never pop the prompt again (there'd be no dialog anyway).
  Future<bool> requestPermission() async {
    if (_fcm == null) return false;
    final settings = await _fcm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final status = settings.authorizationStatus;
    final ok = status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;

    await _vault.markNotifyGranted(ok);
    if (status == AuthorizationStatus.denied) {
      await _vault.markNotifyOsBanned();
    }
    return ok;
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    if (!Platform.isAndroid) return; // iOS shows its own banner
    final n = message.notification;
    if (n == null) return;

    final bigUrl = n.android?.imageUrl;
    AndroidNotificationDetails details = AndroidNotificationDetails(
      _fcmChannelId,
      _fcmChannelName,
      channelDescription: _fcmChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: _notifSmallIcon,
      largeIcon: const DrawableResourceAndroidBitmap(_notifLargeIcon),
    );

    if (bigUrl != null && bigUrl.isNotEmpty) {
      final bytes = await _fetchImage(bigUrl);
      if (bytes != null) {
        details = AndroidNotificationDetails(
          _fcmChannelId,
          _fcmChannelName,
          channelDescription: _fcmChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: _notifSmallIcon,
          largeIcon: const DrawableResourceAndroidBitmap(_notifLargeIcon),
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(bytes),
            largeIcon: const DrawableResourceAndroidBitmap(_notifLargeIcon),
          ),
        );
      }
    }

    final payload = message.data.isEmpty
        ? null
        : jsonEncode(Map<String, dynamic>.from(message.data));

    await _local.show(
      n.hashCode,
      n.title,
      n.body,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  Future<void> _onWarmTap(RemoteMessage message) async {
    final url = extractPushUrl(Map<String, dynamic>.from(message.data));
    if (url != null) onWarmTap?.call(url);
  }

  Future<void> _onColdTap(RemoteMessage message) async {
    final url = extractPushUrl(Map<String, dynamic>.from(message.data));
    if (url != null) await _vault.stashColdTapUrl(url);
  }

  Future<Uint8List?> _fetchImage(String url) async {
    try {
      final resp = await wire
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (_) {}
    return null;
  }
}
