import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/route_mode.dart';

/// Vault — thin persistence facade combining SharedPreferences (fast,
/// non-secret flags) with FlutterSecureStorage (URL and push URL).
///
/// The storage keys are intentionally short and neutral so nothing
/// grep-worthy shows up in a strings dump.
class Vault {
  Vault();

  static const _kMode        = 'r_m';   // route mode
  static const _kPortalUrl   = 'p_url'; // last known good portal url
  static const _kUrlExpires  = 'p_exp'; // portal url expiry epoch (seconds)
  static const _kNotifyGiven = 'n_g';   // user granted push
  static const _kNotifyBanned = 'n_b';  // OS said "denied" — never ask again
  static const _kNotifyDefer = 'n_d';   // epoch (s) after which we can show notify prompt again
  static const _kPushCold    = 'c_url'; // cold-tap URL waiting for consumption

  late SharedPreferences _prefs;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<void> boot() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ─── Route mode ─────────────────────────────────────────────────
  RouteMode currentMode() => RouteMode.restore(_prefs.getString(_kMode));

  Future<void> commitMode(RouteMode mode) =>
      _prefs.setString(_kMode, mode.storageValue);

  // ─── Portal URL (secure) ────────────────────────────────────────
  Future<String?> readPortalUrl() => _secure.read(key: _kPortalUrl);

  Future<void> writePortalUrl(String url) =>
      _secure.write(key: _kPortalUrl, value: url);

  int? portalUrlExpires() => _prefs.getInt(_kUrlExpires);

  Future<void> storePortalUrlExpires(int epoch) =>
      _prefs.setInt(_kUrlExpires, epoch);

  bool isPortalUrlExpired() {
    final e = portalUrlExpires();
    if (e == null) return true;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= e;
  }

  // ─── Push permission ────────────────────────────────────────────
  bool wasNotifyGranted() => _prefs.getBool(_kNotifyGiven) ?? false;
  Future<void> markNotifyGranted(bool v) => _prefs.setBool(_kNotifyGiven, v);

  /// OS "denied" latch — see gray_guide §7 / pitfalls #push.
  /// Once Android says denied, we cannot pop the system prompt again.
  bool wasNotifyOsBanned() => _prefs.getBool(_kNotifyBanned) ?? false;
  Future<void> markNotifyOsBanned() => _prefs.setBool(_kNotifyBanned, true);

  int? notifyDeferUntil() => _prefs.getInt(_kNotifyDefer);
  Future<void> deferNotifyPromptUntil(int epoch) =>
      _prefs.setInt(_kNotifyDefer, epoch);

  bool shouldShowNotifyPrompt() {
    if (wasNotifyGranted()) return false;
    if (wasNotifyOsBanned()) return false;
    final due = notifyDeferUntil();
    if (due == null) return true;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= due;
  }

  // ─── Push URL (cold-tap only, one-shot) ─────────────────────────
  Future<void> stashColdTapUrl(String? url) async {
    if (url == null || url.isEmpty) {
      await _secure.delete(key: _kPushCold);
    } else {
      await _secure.write(key: _kPushCold, value: url);
    }
  }

  Future<String?> pluckColdTapUrl() async {
    final v = await _secure.read(key: _kPushCold);
    if (v != null) await _secure.delete(key: _kPushCold);
    return v;
  }
}
