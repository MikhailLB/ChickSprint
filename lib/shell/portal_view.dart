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
import '../signals/insight.dart';
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

  // Insight funnel state — see .cursor/rules/clarity_analytics.mdc §4.
  bool _offerReached = false; // first successful main-frame load happened
  bool _pageHadError = false; // reset each navigation; blocks false success

  static final RegExp _depositRx = RegExp(
    r'(deposit|cashier|top.?up|replenish|payment|checkout|wallet|пополн|депозит|касс|оплат|внести|платеж)',
    caseSensitive: false,
  );
  static final RegExp _registerRx = RegExp(
    r'(sign.?up|regist|create.?account|onboarding|регистрац|зарегистр)',
    caseSensitive: false,
  );
  static final RegExp _loginRx = RegExp(
    r'(sign.?in|log.?in|log.?on|/auth\b|authoriz|войти|вход|авториз)',
    caseSensitive: false,
  );

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
      ..addJavaScriptChannel('CsInsight',
          onMessageReceived: (m) => _onWebSignal(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (!mounted) return;
          _pageHadError = false;
          setState(() {
            _errored = false;
            _busy = true;
          });
        },
        onPageFinished: (url) {
          if (!mounted) return;
          // pitfalls §4 latch: an inline error page can also fire
          // onPageFinished. If we've already errored, ignore this.
          if (_errored) return;
          setState(() => _busy = false);
          _redirectAttempts = 0;
          _pushSiteAreaOverride();
          _pushKeyboardScroller();
          _installInsightProbe();
          _trackWebPage(url);
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
          Insight.event('web_external');
          Insight.tag('web_external_scheme', scheme);
          _openExternally(uri);
          return NavigationDecision.prevent;
        },
      ));

    _wireAndroid();
    Insight.screen('web');
    Insight.event('web_open');
    _web.loadRequest(Uri.parse(widget.initialUrl));

    widget.pushHub.onWarmTap = (url) {
      if (!mounted) return;
      _web.loadRequest(Uri.parse(url));
    };

    // If the first-launch gateway call was made while offline (or the
    // OneLink hop's network was flaky enough that getToken() returned
    // null), the backend currently thinks push_token is missing. Kick
    // an FCM token refresh now that we're stable inside the portal —
    // if it comes back non-null, the app-scoped onTokenRotate handler
    // re-POSTs the gateway with the fresh token.
    widget.pushHub.ensureFreshToken();

    // Debounced offline detection (pitfalls §3.C) + FCM token
    // refresh when we regain connectivity. Without this, an app
    // booted while offline (or during a flaky OneLink hop) never
    // reports its push token to the backend — the gateway thinks
    // push_token is null and no notifications can be sent.
    _connSub = widget.netSensor.changes.listen((results) {
      final allNone = results.every((r) => r == ConnectivityResult.none);
      if (!allNone) {
        _offlineDebounce?.cancel();
        // Rising edge into "network back up" — chase the FCM token.
        widget.pushHub.ensureFreshToken();
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

    _pageHadError = true;

    final desc = err.description.toLowerCase();
    final String reason = _classifyWebError(err);
    final String failedUrl = _lastMainUrl ?? widget.initialUrl;
    final String host = Uri.tryParse(failedUrl)?.host ?? '';
    Insight.event('web_error');
    Insight.tag('web_error_reason', reason);
    Insight.tag('web_last_error', '${err.errorCode}:${err.description}');
    if (host.isNotEmpty) Insight.tag('web_error_host', host);
    if (!_offerReached) {
      Insight.event('web_offer_unreachable');
      Insight.tag('offer_reached', 'false');
      Insight.tag('offer_unreachable_reason', reason);
    } else {
      Insight.event('web_error_after_load');
    }

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
    // Snapshot the details we'll need to re-launch the portal — the
    // captured references stay valid after this state is torn down.
    final resumeUrl = _lastMainUrl ?? widget.initialUrl;
    final vault = widget.vault;
    final pushHub = widget.pushHub;
    final netSensor = widget.netSensor;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OfflineStage(
          retryScreenBuilder: (_) => PortalView(
            initialUrl: resumeUrl,
            vault: vault,
            pushHub: pushHub,
            netSensor: netSensor,
          ),
        ),
      ),
    );
  }

  void _lockImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lockImmersive();
      Insight.event('web_foreground');
    } else if (state == AppLifecycleState.paused) {
      // "paused inside the WebView" is the cleanest drop-off marker
      // — combined with the last_screen tag it points straight at
      // the offer page a user bounced from.
      Insight.event('web_background');
    }
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
            Builder(builder: (context) {
              final mq = MediaQuery.of(context);
              final landscape = mq.orientation == Orientation.landscape;
              // Portrait: only pad the status-bar height at the top
              //           (immersive hides the nav bar).
              // Landscape: skip the top pad but keep left+right insets
              //            so the WebView content clears the camera
              //            cutout / display cutout on either side.
              final EdgeInsets pad = landscape
                  ? EdgeInsets.only(
                      left: mq.viewPadding.left,
                      right: mq.viewPadding.right,
                    )
                  : EdgeInsets.only(top: mq.viewPadding.top);
              return Padding(
                padding: pad,
                child: WebViewWidget(controller: _web),
              );
            }),
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

  // ── Insight funnel helpers ─────────────────────────────────────

  void _trackWebPage(String url) {
    final Uri? uri = Uri.tryParse(url);
    Insight.screenName(
      'web:${uri == null ? url : '${uri.host}${uri.path}'}',
    );
    Insight.event('web_page');
    Insight.tag('web_last_url', url);
    if (!_offerReached && !_pageHadError) {
      _offerReached = true;
      Insight.event('web_offer_reached');
      Insight.tag('offer_reached', 'true');
      if (uri?.host != null) Insight.tag('offer_host', uri!.host);
    }
    if (_depositRx.hasMatch(url)) {
      Insight.event('web_cashier_page');
      Insight.tag('reached_cashier', 'true');
    }
    _trackAuthPage(url);
  }

  void _trackAuthPage(String url) {
    if (_registerRx.hasMatch(url)) {
      Insight.event('web_register_page');
      Insight.tag('reached_register', 'true');
    } else if (_loginRx.hasMatch(url)) {
      Insight.event('web_login_page');
      Insight.tag('reached_login', 'true');
    }
  }

  static String _classifyWebError(WebResourceError err) {
    final String d = err.description.toLowerCase();
    final int c = err.errorCode;
    if (d.contains('connection_refused') ||
        d.contains('connection refused')) {
      return 'connection_refused';
    }
    if (d.contains('too_many_redirects') ||
        d.contains('too many redirects')) {
      return 'redirect_loop';
    }
    if (d.contains('name_not_resolved') ||
        d.contains('address_unreachable') ||
        d.contains('unknownhost') ||
        c == -2) {
      return 'dns_unresolved';
    }
    if (d.contains('timed out') || d.contains('timeout') || c == -8) {
      return 'timeout';
    }
    if (d.contains('internet_disconnected') ||
        d.contains('network_changed') ||
        c == -6) {
      return 'no_network';
    }
    if (d.contains('connection_reset')) return 'connection_reset';
    if (d.contains('connection_closed') ||
        d.contains('empty_response')) {
      return 'connection_closed';
    }
    if (d.contains('ssl') || d.contains('cert') || c == -11) {
      return 'ssl_error';
    }
    if (d.contains('blocked')) return 'blocked';
    return 'other';
  }

  /// Injects the idempotent JS probe. Reports SPA route changes and
  /// deposit / register / login clicks + auth form submits over the
  /// `CsInsight` JavaScript channel. The DOM inside the WebView is
  /// invisible to Clarity replay — this probe is the only way to
  /// see the offer-side funnel.
  void _installInsightProbe() {
    _web.runJavaScript(r'''
(function(){
  if (window.__csInsight) return; window.__csInsight = true;
  function send(t){ try { CsInsight.postMessage(t); } catch(e){} }
  var DEP=/(deposit|cashier|top.?up|add funds|replenish|payment|pay now|checkout|withdraw|пополн|депозит|касс|оплат|внести|вывод|платеж)/i;
  var REG=/(sign.?up|regist|create.?account|регистрац|зарегистр)/i;
  var LOG=/(sign.?in|log.?in|log.?on|войти|вход|авториз)/i;
  var lastPath='';
  function reportPath(){ var p=location.pathname+location.search; if(p!==lastPath){ lastPath=p; send('path:'+p);} }
  reportPath();
  ['pushState','replaceState'].forEach(function(fn){ var o=history[fn]; history[fn]=function(){ var r=o.apply(this,arguments); setTimeout(reportPath,60); return r; }; });
  window.addEventListener('popstate',function(){ setTimeout(reportPath,60); });
  document.addEventListener('click',function(e){
    try{ var el=e.target;
      for(var i=0;i<4&&el;i++){
        var t=((el.innerText||el.value||(el.getAttribute&&el.getAttribute('aria-label'))||'')+'').trim();
        if(t){ if(DEP.test(t)){send('deposit_click:'+t.slice(0,60));return;}
               if(REG.test(t)){send('register_click:'+t.slice(0,60));return;}
               if(LOG.test(t)){send('login_click:'+t.slice(0,60));return;} }
        el=el.parentElement;
      }
    }catch(x){}
  },true);
  document.addEventListener('submit',function(e){
    try{ var f=e.target;
      var pw=f.querySelectorAll?f.querySelectorAll('input[type="password"]'):[];
      var blob=((f.innerText||'')+' '+(f.getAttribute('action')||'')+' '+(f.className||''));
      var confirm=f.querySelector&&(f.querySelector('input[name*="confirm" i]')||f.querySelector('input[name*="repeat" i]'));
      if(pw&&pw.length>=2){send('auth_submit:register');return;}
      if(pw&&pw.length===1){ send('auth_submit:'+((confirm||REG.test(blob))?'register':'login')); return; }
      if(REG.test(blob)){send('auth_submit:register');return;}
      if(LOG.test(blob)){send('auth_submit:login');return;}
      send('form_submit');
    }catch(x){ send('form_submit'); }
  },true);
})();
''');
  }

  void _onWebSignal(String raw) {
    final int i = raw.indexOf(':');
    final String type = i < 0 ? raw : raw.substring(0, i);
    final String data = i < 0 ? '' : raw.substring(i + 1);
    switch (type) {
      case 'path':
        Insight.event('web_spa_route');
        Insight.tag('web_last_path', data);
        if (_depositRx.hasMatch(data)) {
          Insight.event('web_cashier_page');
          Insight.tag('reached_cashier', 'true');
        }
        _trackAuthPage(data);
        break;
      case 'deposit_click':
        Insight.event('web_deposit_click');
        Insight.tag('deposit_intent', 'true');
        if (data.isNotEmpty) Insight.tag('deposit_label', data);
        break;
      case 'register_click':
        Insight.event('web_register_click');
        Insight.tag('register_intent', 'true');
        break;
      case 'login_click':
        Insight.event('web_login_click');
        Insight.tag('login_intent', 'true');
        break;
      case 'auth_submit':
        if (data == 'register') {
          Insight.event('web_register_submit');
          Insight.tag('attempted_register', 'true');
        } else {
          Insight.event('web_login_submit');
          Insight.tag('attempted_login', 'true');
        }
        break;
      case 'form_submit':
        Insight.event('web_form_submit');
        break;
    }
  }
}
