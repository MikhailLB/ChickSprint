import 'dart:typed_data';

// ---------------------------------------------------------------
// Scrambler — per-project XOR string deobfuscator.
//
// This is intentionally NOT a copy of any sibling project's codec.
// The seed phrase, key-derivation constants, and key length are all
// different, so encoded payloads from other apps do not decode here
// and vice-versa. Static-analysis fingerprinting across apps is the
// whole reason this exists — do not "harmonise" it with anything.
//
// If you rotate the seed, remember to re-encode every payload via
// `tool/encode_keys.dart` and paste the new byte lists into
// env/gateway_keys.dart, env/tracker_keys.dart, and
// core/wire_client.dart.
// ---------------------------------------------------------------

/// Seed bytes for this build. ASCII of a short slug tied to this
/// project only. Change per project.
///   "cs_sprint_rooster" → chick sprint rooster
const List<int> _seedBytes = <int>[
  0x63, 0x73, 0x5F, 0x73, 0x70, 0x72, 0x69, 0x6E,
  0x74, 0x5F, 0x72, 0x6F, 0x6F, 0x73, 0x74, 0x65, 0x72,
];

/// Key length in bytes. 20 is deliberately different from the more
/// common 16-byte size so a scanner keying on `key[i % 16]` never
/// aligns.
const int _keyLen = 20;

Uint8List _deriveKey() {
  if (_seedBytes.isEmpty) return Uint8List(_keyLen);

  // FNV-1a 32-bit mixed with the seed.
  var acc = 0x811C9DC5;
  for (final b in _seedBytes) {
    acc ^= b;
    acc = (acc * 0x01000193) & 0xFFFFFFFF;
  }

  // xorshift32 to fan the mix out into `_keyLen` bytes.
  final key = Uint8List(_keyLen);
  var state = acc == 0 ? 0xDEADBEEF : acc;
  for (var i = 0; i < _keyLen; i++) {
    state ^= (state << 13) & 0xFFFFFFFF;
    state ^= state >> 17;
    state ^= (state << 5) & 0xFFFFFFFF;
    key[i] = state & 0xFF;
  }
  return key;
}

final Uint8List _key = _deriveKey();

/// Decode a scrambled byte list produced by `tool/encode_keys.dart`.
///
/// Returns the plaintext UTF-8 string, or the empty string if [bytes]
/// is empty (which lets callers treat "unset" values gracefully).
String unscramble(List<int> bytes) {
  if (bytes.isEmpty) return '';
  final out = Uint8List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] ^ _key[i % _key.length];
  }
  return String.fromCharCodes(out);
}

/// Complement of [unscramble] — used by the offline encoder tool.
/// Exposed here so both sides read from a single implementation.
Uint8List scramble(String plaintext) {
  final input = Uint8List.fromList(plaintext.codeUnits);
  final out = Uint8List(input.length);
  for (var i = 0; i < input.length; i++) {
    out[i] = input[i] ^ _key[i % _key.length];
  }
  return out;
}
