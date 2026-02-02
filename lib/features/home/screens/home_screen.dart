import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../articles/providers/article_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articlesAsync = ref.watch(articlesStreamProvider);
    final pendingCount = ref.watch(pendingArticlesCountProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            floating: true,
            title: const Text('Library'),
            actions: [
              if (pendingCount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Chip(
                    label: Text(
                      '$pendingCount processing',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.primaryColor,
                      ),
                    ),
                    backgroundColor: context.primaryColor.withOpacity(0.1),
                    side: BorderSide.none,
                    padding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),

          // Content
          articlesAsync.when(
            data: (articles) {
              if (articles.isEmpty) {
                return SliverFillRemaining(
                  child: _EmptyState(),
                );
              }

              // Group by date
              final grouped = <DateTime, List<Article>>{};
              for (final article in articles) {
                final date = DateTime(
                  article.createdAt.year,
                  article.createdAt.month,
                  article.createdAt.day,
                );
                grouped.putIfAbsent(date, () => []).add(article);
              }

              final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final date = dates[index];
                    final dayArticles = grouped[date]!;

                    return _DateSection(
                      date: date,
                      articles: dayArticles,
                    );
                  },
                  childCount: dates.length,
                ),
              );
            },
            loading: () => SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  color: context.primaryColor,
                ),
              ),
            ),
            error: (error, stack) => SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: context.mutedTextColor),
                    const SizedBox(height: 16),
                    Text('Failed to load articles', style: TextStyle(color: context.mutedTextColor)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => ref.invalidate(articlesStreamProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.bookmark_add_outlined,
                size: 40,
                color: context.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Your reading list is empty',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Share articles, blog posts, or any web page to save them here. We\'ll extract the content and prepare your daily digest.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.mutedTextColor,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DateSection extends StatelessWidget {
  final DateTime date;
  final List<Article> articles;

  const _DateSection({
    required this.date,
    required this.articles,
  });

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date == today) {
      return 'Today';
    } else if (date == yesterday) {
      return 'Yesterday';
    } else if (date.isAfter(today.subtract(const Duration(days: 7)))) {
      return DateFormat.EEEE().format(date);
    } else {
      return DateFormat.yMMMd().format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text(
            _formatDate(date),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: context.mutedTextColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        ...articles.map((article) => _ArticleCard(article: article)),
      ],
    );
  }
}

/// Discover-style article card - clean, minimal, Perplexity-inspired
class _ArticleCard extends ConsumerStatefulWidget {
  final Article article;

  const _ArticleCard({required this.article});

  @override
  ConsumerState<_ArticleCard> createState() => _ArticleCardState();
}

class _ArticleCardState extends ConsumerState<_ArticleCard> {
  bool _isPressed = false;

  void _showContextMenu(Article article) {
    final parentContext = context; // Store valid context from widget
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (article.title != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  article.title!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Link'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: article.url));
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  const SnackBar(content: Text('Link copied'), duration: Duration(seconds: 1)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('Copy Summary'),
              onTap: () {
                final title = article.title ?? article.url;
                final keyPoints = article.analysis?.keyPoints ?? [];
                String textToCopy;
                if (keyPoints.isNotEmpty) {
                  final summary = keyPoints.map((p) => '• $p').join('\n');
                  textToCopy = '$title\n\n$summary';
                } else {
                  textToCopy = '$title\n\n${article.url}';
                }
                Clipboard.setData(ClipboardData(text: textToCopy));
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  SnackBar(
                    content: Text(keyPoints.isNotEmpty ? 'Summary copied' : 'Title & link copied'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Archive'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref.read(articleServiceProvider).archive(article.id);
                ref.invalidate(articlesStreamProvider);
                if (parentContext.mounted) {
                  ScaffoldMessenger.of(parentContext).showSnackBar(
                    const SnackBar(content: Text('Archived'), duration: Duration(seconds: 1)),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete(parentContext, article);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext parentContext, Article article) {
    showDialog(
      context: parentContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete article?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Delete immediately and invalidate cache for instant UI update
              await ref.read(articleServiceProvider).delete(article.id);
              ref.invalidate(articlesStreamProvider);
              if (parentContext.mounted) {
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  const SnackBar(content: Text('Deleted'), duration: Duration(seconds: 1)),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isProcessing = article.status == ArticleStatus.pending ||
        article.status == ArticleStatus.extracting ||
        article.status == ArticleStatus.analyzing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          if (!isProcessing) {
            HapticFeedback.lightImpact();
            context.push('/article/${article.id}');
          }
        },
        onTapCancel: () => setState(() => _isPressed = false),
        onLongPress: () {
          setState(() => _isPressed = false);
          _showContextMenu(article);
        },
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: AnimatedOpacity(
            opacity: _isPressed ? 0.9 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFE5E7EB),
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero image
                  if (article.imageUrl != null)
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: isProcessing
                          ? Shimmer.fromColors(
                              baseColor: isDark
                                  ? Colors.grey[800]!
                                  : Colors.grey[300]!,
                              highlightColor: isDark
                                  ? Colors.grey[700]!
                                  : Colors.grey[100]!,
                              child: Container(color: Colors.white),
                            )
                          : CachedNetworkImage(
                              imageUrl: article.imageUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: isDark
                                    ? const Color(0xFF2C2C2E)
                                    : const Color(0xFFF3F4F6),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: isDark
                                    ? const Color(0xFF2C2C2E)
                                    : const Color(0xFFF3F4F6),
                                child: Icon(
                                  Icons.article_outlined,
                                  color: isDark
                                      ? const Color(0xFF6B7280)
                                      : const Color(0xFF9CA3AF),
                                  size: 32,
                                ),
                              ),
                            ),
                    ),

                  // Content
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Metadata row: source + time
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                article.siteName ?? _extractDomain(article.url),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFF9CA3AF)
                                      : const Color(0xFF6B7280),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _formatRelativeTime(article.createdAt),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? const Color(0xFF6B7280)
                                    : const Color(0xFF9CA3AF),
                              ),
                            ),
                            if (isProcessing) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: context.primaryColor,
                                ),
                              ),
                            ] else if (article.readAt == null) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: context.primaryColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 10),

                        // Title
                        if (isProcessing)
                          Shimmer.fromColors(
                            baseColor: isDark
                                ? Colors.grey[800]!
                                : Colors.grey[300]!,
                            highlightColor: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[100]!,
                            child: Container(
                              height: 20,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          )
                        else
                          Text(
                            article.title ?? _extractDomain(article.url),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              color: isDark
                                  ? const Color(0xFFF5F5F5)
                                  : const Color(0xFF1A1A1A),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                        // Key points as bullet summary (with graceful fallback)
                        if (!isProcessing) ...[
                          const SizedBox(height: 10),
                          if (article.analysis?.keyPoints.isNotEmpty == true)
                            ...article.analysis!.keyPoints.take(3).map((point) =>
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 7),
                                        child: Container(
                                          width: 4,
                                          height: 1.5,
                                          color: isDark
                                              ? const Color(0xFF6B7280)
                                              : const Color(0xFF9CA3AF),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          // Strip the label prefix for cleaner display
                                          _stripBulletLabel(point),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w400,
                                            height: 1.45,
                                            color: isDark
                                                ? const Color(0xFFD1D5DB)
                                                : const Color(0xFF4B5563),
                                          ),
                                          maxLines: 4,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                          else if (article.status == ArticleStatus.failed)
                            // Failed extraction - show error state
                            Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 16,
                                  color: isDark
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFFDC2626),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Extraction failed - tap to open in browser',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      height: 1.4,
                                      color: isDark
                                          ? const Color(0xFF9CA3AF)
                                          : const Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else if (article.description != null && article.description!.isNotEmpty)
                            // Has description but no key points - show description
                            Text(
                              article.description!,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                height: 1.4,
                                color: isDark
                                    ? const Color(0xFFD1D5DB)
                                    : const Color(0xFF4B5563),
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            )
                          else
                            // No content at all - show tap to view
                            Row(
                              children: [
                                Icon(
                                  Icons.open_in_new,
                                  size: 16,
                                  color: isDark
                                      ? const Color(0xFF6B7280)
                                      : const Color(0xFF9CA3AF),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Tap to open article',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      height: 1.4,
                                      color: isDark
                                          ? const Color(0xFF9CA3AF)
                                          : const Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  /// Strips the CLAIM:/SIGNIFICANCE:/TAKEAWAY: prefix from bullet points
  /// for cleaner display while keeping the insight content
  String _stripBulletLabel(String point) {
    final prefixes = ['CLAIM:', 'SIGNIFICANCE:', 'TAKEAWAY:'];
    for (final prefix in prefixes) {
      if (point.toUpperCase().startsWith(prefix)) {
        return point.substring(prefix.length).trim();
      }
    }
    return point;
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
    } else if (difference.inDays == 1) {
      return '1d';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else {
      return DateFormat.MMMd().format(dateTime);
    }
  }
}
