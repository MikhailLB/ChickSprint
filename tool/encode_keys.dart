// Offline encoder for the gray-flow secrets.
//
// Run with:
//   dart run tool/encode_keys.dart
//
// DO NOT invoke via PowerShell foreach or bash arithmetic loops.
// Those overflow at 32 bits on Windows and produce corrupted
// byte arrays. Symptom in production:
//   FormatException: Invalid HTTP header field value.
//
// Copy the printed lists into:
//   lib/env/gateway_keys.dart   (config endpoint host + path)
//   lib/env/tracker_keys.dart   (AppsFlyer dev key, GCD host+path,
//                                Firebase project number)
//   lib/core/wire_client.dart   (Chrome + WebKit UA version fragments)

import '../lib/crypto/scrambler.dart';

void _dump(String label, String plaintext) {
  final bytes = scramble(plaintext);
  final hex = bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(', ');
  print('// $label  (len=${bytes.length})');
  print('const <int>[$hex],');
  print('');
}

void main() {
  // ============================================================
  // Fill these in with the real values before shipping. Do NOT
  // commit them to git — the encoded byte lists that this tool
  // prints are what gets committed.
  // ============================================================

  // Gateway (config.php)
  _dump('gateway host', 'https://chicksprint.com');
  _dump('gateway path', '/config.php');

  // AppsFlyer
  _dump('appsflyer dev key', ''); // TODO: paste real key before release
  _dump('gcd host',          'https://gcdsdk.appsflyer.com');
  _dump('gcd path prefix',   '/install_data/v4.0/');

  // Firebase (sender / project number, digits-only string)
  _dump('firebase project number', ''); // TODO: paste real value

  // Real-device User-Agent fragments
  _dump('chrome version', '149.0.7827.163');
  _dump('webkit version', '537.36');
}
