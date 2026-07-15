/// Persisted "which side of the split is this install on".
///
/// Once the gateway answers on first launch, we lock the verdict in
/// [Vault] so subsequent boots skip the attribution race.
enum RouteMode {
  fresh,   // no gateway response yet — do the full first-launch dance
  portal,  // paid install — show the WebView shell
  arena;   // organic / rejected — show the native game

  static RouteMode restore(String? raw) {
    switch (raw) {
      case 'portal':
        return RouteMode.portal;
      case 'arena':
        return RouteMode.arena;
      default:
        return RouteMode.fresh;
    }
  }

  String get storageValue {
    switch (this) {
      case RouteMode.portal:
        return 'portal';
      case RouteMode.arena:
        return 'arena';
      case RouteMode.fresh:
        return 'fresh';
    }
  }
}
