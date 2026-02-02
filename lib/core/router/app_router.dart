import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/screens/home_screen.dart';
import '../../features/articles/screens/article_detail_screen.dart';
import '../../features/digest/screens/digest_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/settings/screens/archive_screen.dart';
import '../../features/auth/screens/web_login_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          name: 'home',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: HomeScreen(),
          ),
        ),
        GoRoute(
          path: '/digest',
          name: 'digest',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DigestScreen(),
          ),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsScreen(),
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/article/:id',
      name: 'article',
      builder: (context, state) => ArticleDetailScreen(
        articleId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/archive',
      name: 'archive',
      builder: (context, state) => const ArchiveScreen(),
    ),
    GoRoute(
      path: '/auth/:provider',
      name: 'auth',
      builder: (context, state) => WebLoginScreen(
        provider: state.pathParameters['provider']!,
        returnUrl: state.uri.queryParameters['returnUrl'],
      ),
    ),
  ],
);

class MainShell extends StatelessWidget {
  final Widget child;
  
  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: const _BottomNav(),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    
    int currentIndex = 0;
    if (location.startsWith('/digest')) currentIndex = 1;
    if (location.startsWith('/settings')) currentIndex = 2;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline,
            width: 0.5,
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/');
              break;
            case 1:
              context.go('/digest');
              break;
            case 2:
              context.go('/settings');
              break;
          }
        },
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        indicatorColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            selectedIcon: Icon(Icons.article),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Daily Digest',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
