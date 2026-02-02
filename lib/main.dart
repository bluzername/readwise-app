import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/auth_extraction_service.dart';
import 'features/articles/providers/article_providers.dart';

// Method channel for native communication
const _shareChannel = MethodChannel('com.readzero.app/share');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase (skip if not configured)
  if (Env.supabaseUrl.isNotEmpty &&
      !Env.supabaseUrl.contains('YOUR_') &&
      Env.supabaseAnonKey.isNotEmpty &&
      !Env.supabaseAnonKey.contains('YOUR_')) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        anonKey: Env.supabaseAnonKey,
      );

      // Auto sign-in anonymously if not logged in
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) {
        debugPrint('No user logged in, signing in anonymously...');
        await client.auth.signInAnonymously();
        debugPrint('Anonymous sign-in successful: ${client.auth.currentUser?.id}');
      } else {
        debugPrint('User already logged in: ${client.auth.currentUser?.id}');
      }
    } catch (e) {
      debugPrint('Supabase initialization failed: $e');
    }
  } else {
    debugPrint('Supabase not configured - running in offline mode');
  }

  runApp(const ProviderScope(child: ReadZeroApp()));
}

class ReadZeroApp extends ConsumerStatefulWidget {
  const ReadZeroApp({super.key});

  @override
  ConsumerState<ReadZeroApp> createState() => _ReadZeroAppState();
}

class _ReadZeroAppState extends ConsumerState<ReadZeroApp> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check for pending URLs after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processPendingUrls();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Check for new shared URLs when app becomes active
    if (state == AppLifecycleState.resumed) {
      _processPendingUrls();
    }
  }

  Future<void> _processPendingUrls() async {
    try {
      final List<dynamic>? urls = await _shareChannel.invokeMethod('getPendingUrls');

      if (urls != null && urls.isNotEmpty) {
        debugPrint('[ReadZero] Processing ${urls.length} pending URLs');
        final List<String> successfulUrls = [];

        for (final url in urls) {
          if (url is String && (url.startsWith('http://') || url.startsWith('https://'))) {
            try {
              // For now, skip X/Twitter and LinkedIn - use Grok API on backend for X
              // LinkedIn will just show "tap to open" fallback
              final isTwitter = url.contains('twitter.com') || url.contains('x.com');
              final isLinkedIn = url.contains('linkedin.com');

              if (isTwitter || isLinkedIn) {
                // Send to backend - Grok will handle X, LinkedIn gets fallback
                debugPrint('[ReadZero] Sending restricted URL to backend: $url');
              }

              // Process all URLs through the backend
              final article = await ref.read(articleServiceProvider).saveArticle(url: url);
              debugPrint('[ReadZero] Article saved: ${article.id}');
              successfulUrls.add(url);
            } catch (e) {
              debugPrint('[ReadZero] Error saving article: $e');
              // Still mark as processed to clear from queue
              successfulUrls.add(url);
            }
          } else {
            successfulUrls.add(url as String);
          }
        }

        // Remove processed URLs
        if (successfulUrls.isNotEmpty) {
          await _shareChannel.invokeMethod('removeProcessedUrls', {'urls': successfulUrls});
          debugPrint('[ReadZero] Cleared ${successfulUrls.length} URLs from queue');
        }
      }
    } catch (e) {
      debugPrint('[ReadZero] Error processing URLs: $e');
    }
  }

  void _showAuthPrompt(String provider, String url) {
    print('[Flutter] _showAuthPrompt called for $provider');
    final providerName = RestrictedDomains.getProviderName(provider);

    // First show a snackbar to confirm the code is running
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$providerName requires login'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Login',
          onPressed: () {
            context.push('/auth/$provider?returnUrl=${Uri.encodeComponent(url)}');
          },
        ),
      ),
    );
    print('[Flutter] SnackBar shown for $provider');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ReadZero',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
