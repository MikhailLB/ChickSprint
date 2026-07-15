import '../crypto/scrambler.dart';

// Config endpoint (a.k.a. `config.php`) — the URL is stored as a
// scrambled byte payload so it does not surface via `strings` on
// the built APK. Regenerate with `dart run tool/encode_keys.dart`
// whenever the scrambler seed changes.

// gateway host  (https://chicksprint.com)
const List<int> _gwHost = <int>[
  0xDC, 0x39, 0x6C, 0x34, 0x05, 0x4B, 0x38, 0x04, 0xEB, 0xCF,
  0x8D, 0x28, 0xC1, 0xD5, 0xE6, 0xED, 0x69, 0x23, 0xF5, 0x1A,
  0xD7, 0x22, 0x75,
];

// gateway path  (/config.php)
const List<int> _gwPath = <int>[
  0x9B, 0x2E, 0x77, 0x2A, 0x10, 0x18, 0x70, 0x05, 0xF8, 0xCF, 0x94,
];

/// Returns the fully-decoded gateway URL used for the POST /config.php.
/// Empty string is a hard failure — callers must treat it as "no
/// gateway configured, fall back to arena".
String buildGatewayUrl() {
  final host = unscramble(_gwHost);
  final path = unscramble(_gwPath);
  if (host.isEmpty || path.isEmpty) return '';
  return '$host$path';
}
