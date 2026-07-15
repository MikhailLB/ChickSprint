import '../crypto/scrambler.dart';

// AppsFlyer / Firebase secrets. Replace the empty byte lists with
// the output of `dart run tool/encode_keys.dart` once real keys
// are provided.

// appsflyer dev key
const List<int> _afDevKey = <int>[
  0xF7, 0x78, 0x5A, 0x0A, 0x18, 0x03, 0x56, 0x40, 0xE6, 0xC8,
  0xAF, 0x0A, 0xFF, 0x90, 0xC2, 0xA7, 0x38, 0x29, 0xE3, 0x03,
  0xE7, 0x22,
];

// firebase project number (sender id, digits-only)
const List<int> _fbSenderId = <int>[
  0x87, 0x7A, 0x2E, 0x71, 0x43, 0x49, 0x2E, 0x1C, 0xBE, 0x9E,
  0xD1, 0x7C,
];

// gcd host  (https://gcdsdk.appsflyer.com)
const List<int> _gcdHost = <int>[
  0xDC, 0x39, 0x6C, 0x34, 0x05, 0x4B, 0x38, 0x04, 0xEF, 0xC4,
  0x80, 0x38, 0xCE, 0xCD, 0xB8, 0xFE, 0x70, 0x3D, 0xF2, 0x52,
  0xD8, 0x34, 0x7D, 0x36, 0x58, 0x12, 0x78, 0x46,
];

// gcd path prefix  (/install_data/v4.0/)
const List<int> _gcdPathPrefix = <int>[
  0x9B, 0x24, 0x76, 0x37, 0x02, 0x10, 0x7B, 0x47, 0xD7, 0xC3,
  0x85, 0x3F, 0xCB, 0x89, 0xE0, 0xAB, 0x2E, 0x7D, 0xAE,
];

String appsFlyerDevKey() => unscramble(_afDevKey);
String firebaseSenderId() => unscramble(_fbSenderId);

/// Builds the raw-attribution retry URL. Follows the AppsFlyer GCD
/// contract: `https://gcdsdk.appsflyer.com/install_data/v4.0/{appId}?devkey=…&device_id={uid}`.
///
/// Query parameters carry the sensitive part (dev key), so we keep
/// them out of the scrambled payload — otherwise the URL length would
/// leak the key length.
String buildGcdUrl({required String appId, required String deviceId}) {
  final host = unscramble(_gcdHost);
  final path = unscramble(_gcdPathPrefix);
  if (host.isEmpty || path.isEmpty) return '';
  final key = appsFlyerDevKey();
  final devKeyPart = key.isEmpty ? '' : 'devkey=$key&';
  return '$host$path$appId?${devKeyPart}device_id=$deviceId';
}
