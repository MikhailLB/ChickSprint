import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/net_sensor.dart';
import '../core/push_hub.dart';
import '../core/vault.dart';
import '../core/wire_client.dart';
import '../env/facade.dart';
import 'offline_stage.dart';

/// Pre-warms the WebView platform. Called via the deferred import so
/// the engine only spins up on the paid-install path.
Future<void> loadPortalEngine() async {
  // Nothing to prefetch synchronously — the engine warms itself when
  // the first WebViewController is instantiated. The empty call
  // exists so the boot stage has a stable API to await.
}

/// PortalView — the full-screen WebView shell.
class PortalView extends StatefulWidget {
  const PortalView({
    super.key,
    required this.initialUrl,
    required this.vault,
    required this.pushHub,
    required this.netSensor,
  });

  final String initialUrl;
  final Vault vault;
  final PushHub pushHub;
  final NetSensor netSensor;

  @override
  State<PortalView> createState() => _PortalViewState();
}

class _PortalViewState extends State<PortalView>
    with WidgetsBindingObserver {
  late final WebViewController _web;
  bool _busy = true;
  bool _errored = false;
  bool _hidden = false;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _offlineDebounce;

  String? _lastMainUrl;
  int _redirectAttempts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Portal must work in both orientations.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _lockImmersive();

    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(wire.userAgent)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() {
            _errored = false;
            _busy = true;
          });
        },
        onPageFinished: (_) {
          if (!mounted) return;
          // pitfalls §4 latch: an inline error page can also fire
          // onPageFinished. If we've already errored, ignore this.
          if (_errored) return;
          setState(() => _busy = false);
          _redirectAttempts = 0;
          _pushSiteAreaOverride();
          _pushKeyboardScroller();
        },
        onWebResourceError: _onWebError,
        onHttpError: (_) {},
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          final scheme = uri.scheme;
          const inlineSchemes = {
            'http',
            'https',
            'about',
            'data',
            'blob',
          };
          if (inlineSchemes.contains(scheme)) {
            if (request.isMainFrame) _lastMainUrl = request.url;
            return NavigationDecision.navigate;
          }
          _openExternally(uri);
          return NavigationDecision.prevent;
        },
      ));

    _wireAndroid();
    _web.loadRequest(Uri.parse(widget.initialUrl));

    widget.pushHub.onWarmTap = (url) {
      if (!mounted) return;
      _web.loadRequest(Uri.parse(url));
    };

    // Debounced offline detection (pitfalls §3.C).
    _connSub = widget.netSensor.changes.listen((results) {
      final allNone = results.every((r) => r == ConnectivityResult.none);
      if (!allNone) {
        _offlineDebounce?.cancel();
        return;
      }
      _offlineDebounce?.cancel();
      _offlineDebounce = Timer(EnvFacade.offlineDebounce, _confirmOffline);
    });
  }

  Future<void> _confirmOffline() async {
    if (_hidden) return;
    final online = await widget.netSensor.online();
    if (online || !mounted) return;
    _showOfflineScreen();
  }

  void _onWebError(WebResourceError err) {
    // pitfalls §4: `isForMainFrame` is null on some WebView vendors;
    // treat null as main frame (only bail on explicit sub-frame).
    if (err.isForMainFrame == false) return;

    final desc = err.description.toLowerCase();

    final tooManyRedirects = desc.contains('too_many_redirects') ||
        desc.contains('too many redirects') ||
        err.errorCode == -1007 ||
        err.errorCode == -9;
    if (tooManyRedirects &&
        _lastMainUrl != null &&
        _redirectAttempts < 3) {
      _redirectAttempts++;
      _web.loadRequest(Uri.parse(_lastMainUrl!));
      return;
    }

    if (!mounted) return;
    setState(() {
      _errored = true;
      _busy = true; // cover the native error page immediately
    });

    final dnsOrDrop =
        desc.contains('name_not_resolved') ||
        desc.contains('err_name_not_resolved') ||
        desc.contains('internet_disconnected') ||
        desc.contains('network_changed') ||
        desc.contains('address_unreachable') ||
        desc.contains('connection_refused') ||
        desc.contains('connection_reset') ||
        desc.contains('connection_timed_out') ||
        err.errorCode == -2 ||
        err.errorCode == -6 ||
        err.errorCode == -7 ||
        err.errorCode == -21 ||
        err.errorCode == -105 ||
        err.errorCode == -106 ||
        err.errorCode == -109 ||
        err.errorCode == -118;

    if (dnsOrDrop) {
      _showOfflineScreen();
    } else {
      _confirmOffline();
    }
  }

  void _showOfflineScreen() {
    if (_hidden) return;
    _hidden = true;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => OfflineStage(
        onRetry: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => PortalView(
            initialUrl: _lastMainUrl ?? widget.initialUrl,
            vault: widget.vault,
            pushHub: widget.pushHub,
            netSensor: widget.netSensor,
          ),
        )),
      ),
    ));
  }

  void _lockImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _lockImmersive();
  }

  void _wireAndroid() {
    if (!Platform.isAndroid) return;
    if (_web.platform is! AndroidWebViewController) return;
    final ctrl = _web.platform as AndroidWebViewController;

    ctrl.setMediaPlaybackRequiresUserGesture(false);
    ctrl.setOnShowFileSelector(_pickFilesForWeb);

    final cookieMgr = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookieMgr.setAcceptThirdPartyCookies(ctrl, true);
  }

  Future<List<String>> _pickFilesForWeb(FileSelectorParams params) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      if (res == null) return const [];
      return res.files
          .where((f) => f.path != null)
          .map((f) => Uri.file(f.path!).toString())
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _openExternally(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // ── JS injections ─────────────────────────────────────────────
  void _pushKeyboardScroller() {
    _web.runJavaScript(r'''
(function() {
  if (window.__csKb) return;
  window.__csKb = true;

  function isEditable(el) {
    if (!el) return false;
    var t = el.tagName;
    return t === 'INPUT' || t === 'TEXTAREA' || el.isContentEditable;
  }

  function reveal() {
    var el = document.activeElement;
    if (!isEditable(el)) return;
    var vp = window.visualViewport;
    if (vp) {
      var r = el.getBoundingClientRect();
      var bot = vp.offsetTop + vp.height;
      if (r.bottom > bot - 20 || r.top < vp.offsetTop) {
        el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
      }
    } else {
      el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
    }
  }

  document.addEventListener('focusin', function(e) {
    if (isEditable(e.target)) setTimeout(reveal, 350);
  });

  if (window.visualViewport) {
    var lastH = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function() {
      var h = window.visualViewport.height;
      if (h < lastH) setTimeout(reveal, 120);
      lastH = h;
    });
  }
})();
''');
  }

  void _pushSiteAreaOverride() {
    _web.runJavaScript(r'''
(function() {
  if (window.__csSafe) return;
  window.__csSafe = true;
  var TAG = '__cs_safe_override';
  var CSS =
    ':root{' +
      '--safe-area-inset-top:0px!important;' +
      '--safe-area-inset-right:0px!important;' +
      '--safe-area-inset-bottom:0px!important;' +
      '--safe-area-inset-left:0px!important;' +
      '--sat:0px!important;--sar:0px!important;' +
      '--sab:0px!important;--sal:0px!important;' +
      '--safe-top:0px!important;--safe-right:0px!important;' +
      '--safe-bottom:0px!important;--safe-left:0px!important;' +
    '}';

  function kbOpen() {
    if (!window.visualViewport) return false;
    return window.visualViewport.height < window.innerHeight * 0.75;
  }

  function apply() {
    if (kbOpen()) return;
    var head = document.head || document.documentElement;
    if (!head) return;
    var meta = document.querySelector('meta[name="viewport"]');
    if (meta) {
      var c = (meta.getAttribute('content') || '')
        .replace(/,?\s*viewport-fit\s*=\s*\w+/ig, '').trim();
      if (!/viewport-fit\s*=\s*contain/i.test(c)) {
        meta.setAttribute('content', c + (c ? ', ' : '') + 'viewport-fit=contain');
      }
    }
    var s = document.getElementById(TAG);
    if (!s) {
      s = document.createElement('style');
      s.id = TAG;
      head.appendChild(s);
    }
    if (s.textContent !== CSS) s.textContent = CSS;
    if (head.lastElementChild !== s) head.appendChild(s);
  }

  apply();

  ['pushState', 'replaceState'].forEach(function(fn) {
    var orig = history[fn];
    history[fn] = function() {
      var r = orig.apply(this, arguments);
      setTimeout(apply, 80);
      setTimeout(apply, 400);
      return r;
    };
  });
  window.addEventListener('popstate', function() { setTimeout(apply, 80); });
  setInterval(apply, 2500);
})();
''');
  }

  // ── Lifecycle ─────────────────────────────────────────────────
  Future<bool> _swallowBack() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _offlineDebounce?.cancel();
    // pitfalls §12: snapshot/restore instead of nulling. We keep the
    // handler active so a warm push arriving between screens still
    // wakes up a reload.
    // (No parent shell handler installed in this project — leaving
    // as null is safe because BootStage sets its own handler on the
    // next entry.)
    widget.pushHub.onWarmTap = null;

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _swallowBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // CRITICAL: must be false so the keyboard adjustResize logic
        // does not fight with Flutter's own resize (pitfalls §keyboard).
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).orientation ==
                        Orientation.landscape
                    ? 0
                    : MediaQuery.of(context).viewPadding.top,
              ),
              child: WebViewWidget(controller: _web),
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFFFB300),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
