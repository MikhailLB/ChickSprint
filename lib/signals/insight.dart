import 'package:clarity_flutter/clarity_flutter.dart';

import '../env/insight_keys.dart';

/// Crash-safe facade over Microsoft Clarity.
///
/// Every call is wrapped in a try/catch — a Clarity failure must never
/// bubble up and break the gray flow. If the SDK is unreachable, if
/// the project id is empty, or if a bad string somehow slips through,
/// the app keeps functioning; only the analytics signal is lost.
///
/// Rules of the road (see .cursor/rules/clarity_analytics.mdc):
/// - Keep event names STABLE and few.
/// - Put high-cardinality values (URLs, hosts, labels) in TAGS.
/// - `identify()` only after `af_id` is known.
class Insight {
  const Insight._();

  static ClarityConfig get config => ClarityConfig(
        projectId: kClarityProjectId,
        // LogLevel.None in release; flip to Verbose when wiring a new
        // project to see the 204 handshake in logcat.
        logLevel: LogLevel.None,
      );

  /// Group the session by AppsFlyer id + attach attribution tags.
  /// No-op on empty id so a missing `af_id` never wipes a good user id.
  static void identify(String? aid, {Map<String, String> tags = const {}}) {
    if (aid != null && aid.isNotEmpty) {
      _guard(() => Clarity.setCustomUserId(_clip(aid, 255)));
      tag('aid', aid);
    }
    tags.forEach(tag);
  }

  /// Native screen: sets the label AND emits a stable per-screen event.
  static void screen(String name) {
    screenName(name);
    event('screen_$name');
  }

  /// Sets the current screen label + mirrors it into the persistent
  /// `last_screen` tag. Clarity keeps the LAST tag value per session,
  /// so filtering by `last_screen` instantly shows the drop-off screen.
  static void screenName(String name) => _guard(() {
        Clarity.setCurrentScreenName(_clip(name, 255));
        Clarity.setCustomTag('last_screen', _clip(name, 255));
      });

  static void event(String name) =>
      _guard(() => Clarity.sendCustomEvent(_clip(name, 254)));

  static void tag(String key, String value) {
    if (value.isEmpty) return;
    _guard(() => Clarity.setCustomTag(key, _clip(value, 255)));
  }

  static String _clip(String v, int max) =>
      v.length <= max ? v : v.substring(0, max);

  static void _guard(void Function() body) {
    try {
      body();
    } catch (_) {}
  }
}
