import 'package:flutter/material.dart';

import 'core/gateway_api.dart';
import 'core/net_sensor.dart';
import 'core/push_hub.dart';
import 'core/tracker_hub.dart';
import 'core/vault.dart';
import 'shell/boot_stage.dart';

class ChickSprintApp extends StatelessWidget {
  const ChickSprintApp({
    super.key,
    required this.vault,
    required this.netSensor,
    required this.trackerHub,
    required this.gatewayApi,
    required this.pushHub,
  });

  final Vault vault;
  final NetSensor netSensor;
  final TrackerHub trackerHub;
  final GatewayApi gatewayApi;
  final PushHub pushHub;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chick Sprint',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFC107),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0700),
      ),
      home: BootStage(
        vault: vault,
        netSensor: netSensor,
        trackerHub: trackerHub,
        gatewayApi: gatewayApi,
        pushHub: pushHub,
      ),
    );
  }
}
