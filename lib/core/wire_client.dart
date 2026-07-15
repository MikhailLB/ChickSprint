import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../crypto/scrambler.dart';

// Chrome and WebKit version fragments — scrambled so version numbers
// don't jump out in a strings dump. Rotate whenever we bump the
// pretend-Chrome version in tool/encode_keys.dart.

// chrome version (149.0.7827.163)
const List<int> _chromeVer = <int>[
  0x85, 0x79, 0x21, 0x6A, 0x46, 0x5F, 0x20, 0x13, 0xBA, 0x90,
  0xCA, 0x7A, 0x9C, 0x95,
];

// webkit version (537.36)
const List<int> _webkitVer = <int>[
  0x81, 0x7E, 0x2F, 0x6A, 0x45, 0x47,
];

String _decodeOr(List<int> b, String fallback) {
  final s = unscramble(b);
  return s.isEmpty ? fallback : s;
}

/// WireClient — the process-wide HTTP client. Injects a realistic
/// mobile browser User-Agent so tracker/backends don't see the
/// telltale `dart:io` UA. The same UA string is applied to the
/// WebView shell (see PortalView) so the two channels line up.
class WireClient extends http.BaseClient {
  WireClient._();
  static final WireClient instance = WireClient._();

  final http.Client _inner = http.Client();
  String? _ua;

  Future<void> boot() async {
    _ua = await _composeUa();
  }

  String get userAgent => _ua ?? _minimalUa();

  Future<String> _composeUa() async {
    final chrome = _decodeOr(_chromeVer, '149.0.7827.163');
    final webkit = _decodeOr(_webkitVer, '537.36');

    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        // `version.release` is the human-facing OS version ("15" on a
        // Galaxy S25, "14" on a Pixel 8) that Chrome puts in its UA.
        // Do NOT use `sdkInt` here — that's 35 for Android 15 and
        // makes the UA read "Android 35" which no real browser sends.
        final release = a.version.release.isNotEmpty
            ? a.version.release
            : '15';
        final brand = a.brand;
        final model = a.model;
        final build = a.display.isNotEmpty ? a.display : a.id;

        return 'Mozilla/5.0 (Linux; Android $release; $brand $model '
            'Build/$build) AppleWebKit/$webkit (KHTML, like Gecko) '
            'Chrome/$chrome Mobile Safari/$webkit';
      }

      final i = await info.iosInfo;
      final ver = i.systemVersion.replaceAll('.', '_');
      return 'Mozilla/5.0 (iPhone; CPU iPhone OS $ver like Mac OS X) '
          'AppleWebKit/$webkit (KHTML, like Gecko) '
          'Version/${i.systemVersion} Mobile/15E148 Safari/$webkit';
    } catch (_) {
      return _minimalUa();
    }
  }

  String _minimalUa() {
    // Fallback used before boot() completes or on device_info failure.
    final chrome = _decodeOr(_chromeVer, '149.0.7827.163');
    final webkit = _decodeOr(_webkitVer, '537.36');
    return Platform.isAndroid
        ? 'Mozilla/5.0 (Linux; Android 15; SM-S931U Build/AP3A.240905.015.A2) '
            'AppleWebKit/$webkit (KHTML, like Gecko) '
            'Chrome/$chrome Mobile Safari/$webkit'
        : 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
            'AppleWebKit/$webkit (KHTML, like Gecko) '
            'Version/17.0 Mobile/15E148 Safari/$webkit';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => userAgent);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Handy shortcut — the rest of the codebase just imports this.
final WireClient wire = WireClient.instance;
