import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../env/facade.dart';

/// Set of `ConnectivityResult` values that count as "the device *has*
/// a network interface". VPN, Bluetooth and Other are treated as real
/// connections — otherwise the app briefly flashes the offline screen
/// every time the user toggles their tunnel (see pitfalls §3.A).
const Set<ConnectivityResult> _liveInterfaces = <ConnectivityResult>{
  ConnectivityResult.wifi,
  ConnectivityResult.mobile,
  ConnectivityResult.ethernet,
  ConnectivityResult.vpn,
  ConnectivityResult.bluetooth,
  ConnectivityResult.other,
};

/// Hosts used for the DNS probe. Try in order — first that resolves
/// wins. Kept as generic public roots so the choice doesn't fingerprint
/// the app.
const List<String> _probeHosts = <String>[
  'cloudflare.com',
  'wikipedia.org',
  'apple.com',
];

class NetSensor {
  NetSensor([Connectivity? c]) : _plugin = c ?? Connectivity();

  final Connectivity _plugin;

  /// Cheap, deterministic online check.
  ///
  ///  * If there is no live interface at all → false immediately.
  ///  * Otherwise, race DNS lookups over `_probeHosts`; whichever
  ///    resolves first flips the answer to true.
  ///  * Any resolution beats the [EnvFacade.dnsProbeTimeout] wall.
  Future<bool> online() async {
    final results = await _plugin.checkConnectivity();
    if (!results.any(_liveInterfaces.contains)) return false;

    final probes = _probeHosts.map(_probeHost).toList(growable: false);
    try {
      return await Future.any(probes).timeout(EnvFacade.dnsProbeTimeout);
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _probeHost(String host) async {
    try {
      final answer = await InternetAddress.lookup(host);
      return answer.isNotEmpty && answer.first.rawAddress.isNotEmpty;
    } catch (_) {
      // Bury this — Future.any() will settle on a peer that succeeds,
      // or the overall timeout will fire and we'll return false.
      final never = Completer<bool>();
      return never.future;
    }
  }

  /// Raw stream from connectivity_plus. Consumers must debounce before
  /// routing to the offline screen — see pitfalls §3.C.
  Stream<List<ConnectivityResult>> get changes =>
      _plugin.onConnectivityChanged;
}
