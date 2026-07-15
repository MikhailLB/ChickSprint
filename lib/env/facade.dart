import 'gateway_keys.dart';
import 'site_endpoints.dart';
import 'tracker_keys.dart';

/// EnvFacade — single, boring accessor for every project-wide
/// constant. All callers should read from here so renames stay
/// isolated to one file.
class EnvFacade {
  EnvFacade._();

  // Identity.
  static const String bundleId = 'com.chicksprint.chicksprintgame';
  static const String storeId  = 'com.chicksprint.chicksprintgame';
  static const String appName  = 'ChickSprint';
  static const String iosStoreNumericId = '';

  // Networking.
  static String get gatewayUrl => buildGatewayUrl();
  static String get trackerDevKey => appsFlyerDevKey();
  static String get pushSenderId => firebaseSenderId();

  // Public pages.
  static String get sitePage => siteHomeUrl;
  static String get privacyPage => privacyPolicyUrl;
  static String get supportPage => supportPageUrl;

  // Attribution retry cadence.
  //
  //  - `attributionSdkTimeout`   caps the first SDK callback race.
  //  - `attributionSdkReturning` shorter cap for returning users.
  //  - `deepLinkTimeout`         cap for UDL callback.
  //  - `organicRetryDelay`       delay before we hit GCD when the
  //                              first SDK callback lied "Organic".
  //  - `gatewayTimeout`          POST /config.php.
  //  - `gcdPollWindow`           §11 rescue path: how long we keep
  //                              hitting GCD when the SDK stalled but
  //                              the deep-link callback looked paid.
  //  - `gcdPollInterval`         wait between GCD pokes.
  static const Duration attributionSdkTimeout   = Duration(seconds: 25);
  static const Duration attributionSdkReturning = Duration(seconds: 10);
  static const Duration deepLinkTimeout         = Duration(seconds: 5);
  static const Duration organicRetryDelay       = Duration(seconds: 5);
  static const Duration gatewayTimeout          = Duration(seconds: 15);
  static const Duration gcdPollWindow           = Duration(seconds: 90);
  static const Duration gcdPollInterval         = Duration(seconds: 4);

  // "Skip" cool-down for the push permission prompt (3 days per TZ).
  static const int notifyCooldownSeconds = 3 * 24 * 60 * 60;

  // No-internet screen debounce — absorbs the momentary
  // `[ConnectivityResult.none]` burst when a VPN interface flips.
  static const Duration offlineDebounce = Duration(milliseconds: 700);

  // DNS-probe timeout. Real "no route" hits SocketException instantly,
  // so 7s is only paid when the tunnel is slow.
  static const Duration dnsProbeTimeout = Duration(seconds: 7);
}
