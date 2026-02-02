// WebView-based login screen for restricted content providers (LinkedIn, Twitter/X)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/services/auth_extraction_service.dart';
import '../../../core/theme/app_theme.dart';

/// Login screen using WKWebView to capture authentication cookies
class WebLoginScreen extends StatefulWidget {
  final String provider; // 'linkedin' or 'twitter'
  final String? returnUrl; // URL to extract after login

  const WebLoginScreen({
    super.key,
    required this.provider,
    this.returnUrl,
  });

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _loginDetected = false;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    final loginUrl = RestrictedDomains.getLoginUrl(widget.provider);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(AuthExtractionService.safariUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });
          },
          onPageFinished: (url) async {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });
            await _checkLoginStatus(url);
          },
          onNavigationRequest: (request) {
            // Allow all navigation during login flow
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(loginUrl));
  }

  Future<void> _checkLoginStatus(String url) async {
    if (_loginDetected) return;

    // Check if we've navigated away from login page (indicates success)
    bool isLoggedIn = false;

    if (widget.provider == 'linkedin') {
      // LinkedIn: After login, redirects to feed or the original URL
      isLoggedIn = url.contains('linkedin.com/feed') ||
                   url.contains('linkedin.com/in/') ||
                   url.contains('linkedin.com/posts/') ||
                   (url.contains('linkedin.com') && !url.contains('/login') && !url.contains('/checkpoint'));
    } else if (widget.provider == 'twitter') {
      // Twitter/X: After login, redirects to home or the original URL
      isLoggedIn = url.contains('twitter.com/home') ||
                   url.contains('x.com/home') ||
                   ((url.contains('twitter.com') || url.contains('x.com')) &&
                    !url.contains('/login') &&
                    !url.contains('/i/flow'));
    }

    if (isLoggedIn) {
      _loginDetected = true;
      await _extractAndStoreCookies();
    }
  }

  Future<void> _extractAndStoreCookies() async {
    try {
      // Get cookies from WebView using JavaScript
      final cookiesJson = await _controller.runJavaScriptReturningResult(
        'document.cookie'
      );

      // Clean up the result (remove quotes)
      String cookies = cookiesJson.toString();
      if (cookies.startsWith('"') && cookies.endsWith('"')) {
        cookies = cookies.substring(1, cookies.length - 1);
      }

      if (cookies.isNotEmpty) {
        // Store cookies
        await CookieStorageService.storeCookies(widget.provider, cookies);

        if (mounted) {
          // Show success and return
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Logged into ${RestrictedDomains.getProviderName(widget.provider)}'),
              duration: const Duration(seconds: 2),
            ),
          );

          // Return success with the URL to extract
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      debugPrint('[WebLogin] Error extracting cookies: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final providerName = RestrictedDomains.getProviderName(widget.provider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Login to $providerName'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _isLoading
              ? LinearProgressIndicator(color: context.primaryColor)
              : const SizedBox.shrink(),
        ),
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: context.primaryColor.withOpacity(0.1),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: context.primaryColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Login once to extract content from $providerName. Your credentials are stored securely on-device.',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // WebView
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}

/// Helper to show login screen and wait for result
Future<bool> showLoginScreen(BuildContext context, String provider, {String? returnUrl}) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (context) => WebLoginScreen(
        provider: provider,
        returnUrl: returnUrl,
      ),
      fullscreenDialog: true,
    ),
  );
  return result ?? false;
}
