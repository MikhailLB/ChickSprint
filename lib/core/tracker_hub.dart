import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../env/facade.dart';
import '../env/tracker_keys.dart';
import 'wire_client.dart';

/// TrackerHub — AppsFlyer SDK owner.
///
/// Contract:
///   • Two callbacks fill in `install` and `deepLink` maps.
///   • `awaitInstallData()` and `awaitDeepLink()` are Futures that
///     complete when the SDK delivers (or the surrounding router
///     times them out).
///   • If the SDK lies "Organic" on first callback we hit the GCD
///     endpoint after a short delay and use whichever payload we
///     receive as the authoritative attribution.
///   • [rescueViaGcd] handles pitfalls §11 — kicks in when the SDK
///     never fires but the deep-link callback proved this was paid.
///   • [assemblePayload] merges everything into the exact shape the
///     backend expects. Do not sanitise / rename attribution fields.
class TrackerHub {
  AppsflyerSdk? _sdk;

  Map<String, dynamic>? _install;
  Map<String, dynamic>? _deepLink;
  Map<String, dynamic>? _appOpen;

  final Completer<Map<String, dynamic>> _installReady =
      Completer<Map<String, dynamic>>();
  final Completer<void> _deepLinkReady = Completer<void>();

  bool _booted = false;

  bool get hasInstallData =>
      _install != null && _install!.isNotEmpty;

  /// True when the UDL callback delivered something that looks like
  /// a real click (as opposed to AppsFlyer's `deep_link_test` stub).
  bool get deepLinkLooksPaid {
    final d = _deepLink;
    if (d == null || d.isEmpty) return false;
    bool liveField(String k) {
      final v = d[k];
      if (v is! String) return false;
      final s = v.trim();
      return s.isNotEmpty && s.toLowerCase() != 'deep_link_test';
    }
    return liveField('deep_link_value') ||
        liveField('deep_link_sub1') ||
        liveField('shortlink');
  }

  Future<void> boot() async {
    if (_booted) return;
    _booted = true;

    final devKey = EnvFacade.trackerDevKey;
    if (devKey.isEmpty) {
      // Still finish the completers so the router doesn't sit forever
      // waiting for callbacks that will never come.
      if (!_installReady.isCompleted) _installReady.complete(<String, dynamic>{});
      if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
      return;
    }

    final opts = AppsFlyerOptions(
      afDevKey: devKey,
      appId: EnvFacade.iosStoreNumericId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );
    _sdk = AppsflyerSdk(opts);

    _sdk!.onInstallConversionData(_handleInstallCallback);
    _sdk!.onAppOpenAttribution(_handleAppOpenCallback);
    _sdk!.onDeepLinking(_handleDeepLinkCallback);

    await _sdk!.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
  }

  Future<Map<String, dynamic>> awaitInstallData() {
    return _installReady.future.timeout(
      EnvFacade.attributionSdkTimeout,
      onTimeout: () => <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> awaitInstallDataQuick() {
    return _installReady.future.timeout(
      EnvFacade.attributionSdkReturning,
      onTimeout: () => <String, dynamic>{},
    );
  }

  Future<void> awaitDeepLink() {
    return _deepLinkReady.future
        .timeout(EnvFacade.deepLinkTimeout, onTimeout: () {});
  }

  Future<String?> deviceUid() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  // ─── Callbacks ──────────────────────────────────────────────────

  Future<void> _handleInstallCallback(dynamic data) async {
    final payload = _extractMap(data);
    if (payload == null) return;

    if (payload['af_status'] == 'Organic') {
      // Suspect false-organic (see gray_guide §attribution).
      await Future<void>.delayed(EnvFacade.organicRetryDelay);
      final refreshed = await _hitGcd();
      _install = refreshed ?? payload;
    } else {
      _install = payload;
    }

    if (!_installReady.isCompleted) {
      _installReady.complete(_install!);
    }
  }

  void _handleAppOpenCallback(dynamic data) {
    _appOpen = _extractMap(data);
  }

  void _handleDeepLinkCallback(dynamic result) {
    try {
      final r = result as DeepLinkResult?;
      if (r != null && r.deepLink != null) {
        _deepLink = r.deepLink!.clickEvent;
      }
    } catch (_) {}
    if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
  }

  Map<String, dynamic>? _extractMap(dynamic data) {
    if (data is Map) {
      final wrapped = data['payload'];
      if (wrapped is Map) return Map<String, dynamic>.from(wrapped);
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  // ─── §11 GCD rescue ─────────────────────────────────────────────

  /// Called only when the SDK stalled but the deep-link callback
  /// proved this install came from a real click. Polls GCD in a loop
  /// until it delivers a non-error `af_status`, the [_installReady]
  /// future is otherwise completed, or the poll window expires.
  Future<void> rescueViaGcd() async {
    if (_installReady.isCompleted) return;
    if (EnvFacade.trackerDevKey.isEmpty) return;

    final deadline = DateTime.now().add(EnvFacade.gcdPollWindow);
    while (!_installReady.isCompleted &&
        DateTime.now().isBefore(deadline)) {
      final fresh = await _hitGcd();
      if (_installReady.isCompleted) return;
      if (fresh != null) {
        final status = fresh['af_status']?.toString() ?? '';
        if (status.isNotEmpty && status != 'error') {
          _install = fresh;
          if (!_installReady.isCompleted) {
            _installReady.complete(fresh);
          }
          return;
        }
      }
      await Future<void>.delayed(EnvFacade.gcdPollInterval);
    }
  }

  Future<Map<String, dynamic>?> _hitGcd() async {
    try {
      final uid = await deviceUid();
      if (uid == null || uid.isEmpty) return null;

      final appId = Platform.isIOS
          ? EnvFacade.iosStoreNumericId
          : EnvFacade.bundleId;
      final url = buildGcdUrl(appId: appId, deviceId: uid);
      if (url.isEmpty) return null;

      final resp = await wire
          .get(
            Uri.parse(url),
            headers: {
              'authorization': 'Bearer ${EnvFacade.trackerDevKey}',
              'accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─── Payload builder ────────────────────────────────────────────

  Future<Map<String, dynamic>> assemblePayload({
    required String locale,
    String? pushToken,
  }) async {
    // Order matters — install data wins over deep-link and app-open,
    // both of which use putIfAbsent so we never clobber a real key.
    final body = <String, dynamic>{};
    if (_install != null) body.addAll(_install!);
    _deepLink?.forEach((k, v) => body.putIfAbsent(k, () => v));
    _appOpen?.forEach((k, v) => body.putIfAbsent(k, () => v));

    body['af_id']     = await deviceUid() ?? '';
    body['bundle_id'] = EnvFacade.bundleId;
    body['os']        = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id']  = EnvFacade.storeId;
    body['locale']    = locale;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    final senderId = EnvFacade.pushSenderId;
    if (senderId.isNotEmpty) {
      body['firebase_project_id'] = senderId;
    }

    if (kDebugMode) {
      debugPrint('[TrackerHub] payload=${jsonEncode(body)}');
    }
    return body;
  }
}
