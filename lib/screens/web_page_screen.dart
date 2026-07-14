import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebPageScreen extends StatefulWidget {
  const WebPageScreen({
    super.key,
    required this.title,
    required this.url,
  });

  final String title;
  final String url;

  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p),
          onPageStarted: (_) => setState(() {
            _finished = false;
            _progress = 0;
          }),
          onPageFinished: (_) => setState(() {
            _finished = true;
            _progress = 100;
          }),
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFC107),
        foregroundColor: const Color(0xFF3E2723),
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        elevation: 4,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (!_finished)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _progress / 100,
                minHeight: 3,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFFF9800),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
