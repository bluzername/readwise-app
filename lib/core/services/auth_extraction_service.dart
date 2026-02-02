// Authentication-based content extraction for restricted sites (LinkedIn, Twitter/X)
// Uses on-device WKWebView with stored cookies to extract content

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Domains that require authentication for content extraction
class RestrictedDomains {
  static const linkedin = ['linkedin.com', 'www.linkedin.com'];
  static const twitter = ['twitter.com', 'www.twitter.com', 'x.com', 'www.x.com'];

  static const all = [...linkedin, ...twitter];

  static String? getProvider(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    final host = uri.host.toLowerCase();
    if (linkedin.any((d) => host.contains(d))) return 'linkedin';
    if (twitter.any((d) => host.contains(d))) return 'twitter';
    return null;
  }

  static bool isRestricted(String url) => getProvider(url) != null;

  static String getLoginUrl(String provider) {
    switch (provider) {
      case 'linkedin':
        return 'https://www.linkedin.com/login';
      case 'twitter':
        return 'https://twitter.com/i/flow/login';
      default:
        throw ArgumentError('Unknown provider: $provider');
    }
  }

  static String getProviderName(String provider) {
    switch (provider) {
      case 'linkedin':
        return 'LinkedIn';
      case 'twitter':
        return 'X (Twitter)';
      default:
        return provider;
    }
  }
}

/// Stored cookie data with timestamp
class StoredCookies {
  final String provider;
  final String cookiesJson;
  final DateTime storedAt;

  StoredCookies({
    required this.provider,
    required this.cookiesJson,
    required this.storedAt,
  });

  bool get isExpired {
    final age = DateTime.now().difference(storedAt);
    return age.inDays > 30; // Expire after 30 days
  }

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'cookiesJson': cookiesJson,
    'storedAt': storedAt.toIso8601String(),
  };

  factory StoredCookies.fromJson(Map<String, dynamic> json) => StoredCookies(
    provider: json['provider'] as String,
    cookiesJson: json['cookiesJson'] as String,
    storedAt: DateTime.parse(json['storedAt'] as String),
  );
}

/// Manages cookie storage in secure keychain
class CookieStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static String _key(String provider) => 'auth_cookies_$provider';

  /// Store cookies for a provider
  static Future<void> storeCookies(String provider, String cookiesJson) async {
    final stored = StoredCookies(
      provider: provider,
      cookiesJson: cookiesJson,
      storedAt: DateTime.now(),
    );
    await _storage.write(key: _key(provider), value: jsonEncode(stored.toJson()));
    debugPrint('[AuthExtraction] Stored cookies for $provider');
  }

  /// Get stored cookies if valid (not expired)
  static Future<StoredCookies?> getCookies(String provider) async {
    final json = await _storage.read(key: _key(provider));
    if (json == null) return null;

    try {
      final stored = StoredCookies.fromJson(jsonDecode(json));
      if (stored.isExpired) {
        debugPrint('[AuthExtraction] Cookies for $provider expired');
        await _storage.delete(key: _key(provider));
        return null;
      }
      return stored;
    } catch (e) {
      debugPrint('[AuthExtraction] Error reading cookies: $e');
      return null;
    }
  }

  /// Check if we have valid cookies for a provider
  static Future<bool> hasValidCookies(String provider) async {
    final cookies = await getCookies(provider);
    return cookies != null;
  }

  /// Clear cookies for a provider
  static Future<void> clearCookies(String provider) async {
    await _storage.delete(key: _key(provider));
    debugPrint('[AuthExtraction] Cleared cookies for $provider');
  }

  /// Clear all stored cookies
  static Future<void> clearAll() async {
    for (final provider in ['linkedin', 'twitter']) {
      await _storage.delete(key: _key(provider));
    }
    debugPrint('[AuthExtraction] Cleared all cookies');
  }
}

/// Result of content extraction
class ExtractedContent {
  final String? title;
  final String? content;
  final String? imageUrl;
  final String? author;
  final String? error;

  ExtractedContent({
    this.title,
    this.content,
    this.imageUrl,
    this.author,
    this.error,
  });

  bool get isSuccess => error == null && content != null && content!.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
    'imageUrl': imageUrl,
    'author': author,
    'error': error,
  };
}

/// Service for authenticated content extraction using native WebView
class AuthExtractionService {
  static const _channel = MethodChannel('com.readzero.app/auth_extraction');

  /// Safari on iPhone user agent
  static const safariUserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  /// Check if URL needs authenticated extraction
  static bool needsAuth(String url) => RestrictedDomains.isRestricted(url);

  /// Check if we can extract (have valid cookies)
  static Future<bool> canExtract(String url) async {
    final provider = RestrictedDomains.getProvider(url);
    if (provider == null) return false;
    return CookieStorageService.hasValidCookies(provider);
  }

  /// Extract content using stored cookies (called from native side)
  static Future<ExtractedContent> extractContent(String url) async {
    final provider = RestrictedDomains.getProvider(url);
    if (provider == null) {
      return ExtractedContent(error: 'Not a restricted domain');
    }

    final cookies = await CookieStorageService.getCookies(provider);
    if (cookies == null) {
      return ExtractedContent(error: 'No valid cookies - login required');
    }

    try {
      final result = await _channel.invokeMethod<Map>('extractContent', {
        'url': url,
        'cookies': cookies.cookiesJson,
        'userAgent': safariUserAgent,
        'provider': provider,
      });

      if (result == null) {
        return ExtractedContent(error: 'Extraction returned null');
      }

      return ExtractedContent(
        title: result['title'] as String?,
        content: result['content'] as String?,
        imageUrl: result['imageUrl'] as String?,
        author: result['author'] as String?,
        error: result['error'] as String?,
      );
    } on PlatformException catch (e) {
      debugPrint('[AuthExtraction] Platform error: ${e.message}');
      return ExtractedContent(error: e.message);
    }
  }
}
