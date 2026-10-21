import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Cloudflare Turnstile challenge. The secret key is only used by the Edge
/// Function; this public site key is safe to ship in the client.
class TurnstileCaptcha extends StatefulWidget {
  const TurnstileCaptcha({super.key, required this.onToken});

  final ValueChanged<String> onToken;

  @override
  State<TurnstileCaptcha> createState() => TurnstileCaptchaState();
}

class TurnstileCaptchaState extends State<TurnstileCaptcha> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    _loadWidget();
  }

  Future<void> _loadWidget() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      if (!_configured) {
        await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        if (_controller.platform is AndroidWebViewController) {
          final androidController =
              _controller.platform as AndroidWebViewController;
          final cookieManager =
              WebViewCookieManager().platform as AndroidWebViewCookieManager;
          await cookieManager.setAcceptThirdPartyCookies(
            androidController,
            true,
          );
        }
        await _controller.addJavaScriptChannel(
          'Turnstile',
          onMessageReceived: (message) {
            if (mounted) widget.onToken(message.message);
          },
        );
        _configured = true;
      }

      // Fetch the hosted HTML and explicitly load it as HTML. Some Supabase
      // gateways/clients return the body as text even when the function sets
      // text/html, which otherwise makes the WebView show source code.
      final pageUri = Uri.parse(
        'https://bxtsqeminradevdspwoa.supabase.co/functions/v1/turnstile-widget',
      );
      final pageResponse = await http
          .get(pageUri)
          .timeout(const Duration(seconds: 20));
      if (pageResponse.statusCode != 200) {
        throw Exception('Challenge page returned ${pageResponse.statusCode}');
      }
      await _controller.loadHtmlString(
        pageResponse.body,
        baseUrl: pageUri.origin,
      );
      if (mounted) setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> reset() async {
    try {
      await _controller.runJavaScript(
        'if(window.turnstile){window.turnstile.reset()}',
      );
    } catch (_) {
      // A challenge can be reset while its platform view is being disposed.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadFailed) {
      return SizedBox(
        height: 72,
        child: Center(
          child: TextButton.icon(
            onPressed: _loadWidget,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry security check'),
          ),
        ),
      );
    }
    return SizedBox(
      height: 72,
      child: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }
}
