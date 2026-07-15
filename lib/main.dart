import 'dart:async';
import 'dart:io';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_root.dart';
import 'core/gateway_api.dart';
import 'core/net_sensor.dart';
import 'core/push_hub.dart';
import 'core/tracker_hub.dart';
import 'core/vault.dart';
import 'core/wire_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase + App Check. App Check swallows a bunch of production
  // 403s from the gateway when the debug provider is not registered
  // in the Firebase console. See gray guide bug #7.
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } catch (_) {
    // Firebase not configured — the app continues without Firebase
    // (no push, no App Check). Gateway still works.
  }

  // Loading + Portal need both orientations. The white game locks
  // itself back to portrait when it takes over.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0700),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  await wire.boot();

  final vault = Vault();
  await vault.boot();

  final netSensor = NetSensor();
  final trackerHub = TrackerHub();
  final gatewayApi = GatewayApi(vault);
  final pushHub = PushHub(vault);

  // Install the token-rotate handler once, at app scope, so it keeps
  // firing across BootStage → PortalView transitions. If we regain
  // internet later (or FCM issues a fresh token), the gateway learns
  // the new push_token immediately — otherwise the backend keeps
  // thinking this install has no token and never sends notifications.
  pushHub.onTokenRotate = (freshToken) async {
    try {
      final locale = Platform.localeName.replaceAll('-', '_');
      final payload = await trackerHub.assemblePayload(
        locale: locale,
        pushToken: freshToken,
      );
      unawaited(gatewayApi.submit(payload));
    } catch (_) {}
  };

  runApp(ChickSprintApp(
    vault: vault,
    netSensor: netSensor,
    trackerHub: trackerHub,
    gatewayApi: gatewayApi,
    pushHub: pushHub,
  ));
}
