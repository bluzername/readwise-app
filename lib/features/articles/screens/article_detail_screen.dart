import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../articles/providers/article_providers.dart';
import '../widgets/discover_card.dart';

/// Extract domain from URL for display
String _extractDomain(String url) {
  try {
    final uri = Uri.parse(url);
    return uri.host.replaceFirst('www.', '');
  } catch (_) {
    return url;
  }
}

class ArticleDetailScreen extends ConsumerStatefulWidget {
  final String articleId;

  const ArticleDetailScreen({super.key, required this.articleId});

  @override
  ConsumerState<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends ConsumerState<ArticleDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  double _scrollProgress = 0;
  bool _showSummary = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Mark as read after a short delay
    Future.delayed(const Duration(seconds: 2), () {
      ref.read(articleServiceProvider).markAsRead(widget.articleId);
    });
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      setState(() {
        _scrollProgress = maxScroll > 0 ? (currentScroll / maxScroll).clamp(0, 1) : 0;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final articleAsync = ref.watch(articleProvider(widget.articleId));

    return articleAsync.when(
      data: (article) => _buildContent(context, article),
      loading: () => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: CircularProgressIndicator(color: context.primaryColor),
        ),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: context.mutedTextColor),
              const SizedBox(height: 16),
              Text('Failed to load article'),
              TextButton(
                onPressed: () => ref.invalidate(articleProvider(widget.articleId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Article article) {
    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // App Bar with progress indicator
          SliverAppBar(
            floating: true,
            pinned: true,
            expandedHeight: article.imageUrl != null ? 250 : 0,
            flexibleSpace: article.imageUrl != null
                ? FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: article.imageUrl!,
                          fit: BoxFit.cover,
                        ),
                        // Gradient overlay
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.7),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(3),
              child: LinearProgressIndicator(
                value: _scrollProgress,
                backgroundColor: Colors.transparent,
                color: context.primaryColor,
                minHeight: 3,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.open_in_browser),
                onPressed: () => launchUrl(Uri.parse(article.url)),
                tooltip: 'Open in browser',
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'archive':
                      ref.read(articleServiceProvider).archive(article.id);
                      Navigator.of(context).pop();
                      break;
                    case 'delete':
                      _showDeleteConfirmation(context, article);
                      break;
                    case 'share':
                      Clipboard.setData(ClipboardData(text: article.url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('URL copied to clipboard')),
                      );
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.share_outlined, size: 20),
                        SizedBox(width: 12),
                        Text('Copy link'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'archive',
                    child: Row(
                      children: [
                        Icon(Icons.archive_outlined, size: 20),
                        SizedBox(width: 12),
                        Text('Archive'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 20, color: Colors.red),
                        SizedBox(width: 12),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Article content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Meta info
                  if (article.siteName != null || article.author != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          if (article.siteName != null)
                            Text(
                              article.siteName!,
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: context.primaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          if (article.siteName != null && article.author != null)
                            Text(
                              ' • ',
                              style: TextStyle(color: context.mutedTextColor),
                            ),
                          if (article.author != null)
                            Text(
                              article.author!,
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: context.mutedTextColor,
                                  ),
                            ),
                        ],
                      ),
                    ),

                  // Title
                  Text(
                    article.title ?? 'Untitled',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),

                  const SizedBox(height: 12),

                  // Reading time and date
                  Row(
                    children: [
                      if (article.analysis?.readingTimeMinutes != null) ...[
                        Icon(
                          Icons.schedule_outlined,
                          size: 16,
                          color: context.mutedTextColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${article.analysis!.readingTimeMinutes} min read',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 16),
                      ],
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: context.mutedTextColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat.yMMMd().format(article.createdAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Fallback UI for failed/empty articles
                  if (_isArticleEmpty(article)) ...[
                    _buildEmptyArticleFallback(context, article),
                    const SizedBox(height: 24),
                  ],

                  // AI Summary Card - Key Points (3 bullets)
                  if (article.analysis != null && !_isArticleEmpty(article)) ...[
                    _buildSummarySection(
                      context,
                      title: 'Key Takeaways',
                      icon: Icons.lightbulb_outline,
                      bullets: article.analysis!.keyPoints,
                    ),
                    const SizedBox(height: 20),

                    // Detailed Summary (5-10 bullets) if available
                    if (article.analysis!.detailedPoints.isNotEmpty) ...[
                      _buildSummarySection(
                        context,
                        title: 'Deeper Dive',
                        icon: Icons.menu_book_outlined,
                        bullets: article.analysis!.detailedPoints,
                        isExpanded: false,
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Source link
                    _buildSourceLink(context, article),
                    const SizedBox(height: 24),
                  ],

                  // Image analyses
                  if (article.analysis?.imageAnalyses.isNotEmpty == true) ...[
                    const SizedBox(height: 32),
                    _ImageAnalysesSection(
                      images: article.analysis!.imageAnalyses,
                    ),
                  ],

                  // Comments section
                  if (article.comments.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    _CommentsSection(
                      comments: article.comments,
                      commentsSummary: article.analysis?.commentsSummary,
                    ),
                  ],

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Check if article has failed extraction or has no meaningful content
  bool _isArticleEmpty(Article article) {
    // Only show fallback for explicitly failed articles
    if (article.status == ArticleStatus.failed) return true;

    // If status is ready but we have no content AND no analysis, extraction failed silently
    if (article.status == ArticleStatus.ready &&
        article.content == null &&
        article.analysis == null) return true;

    return false;
  }

  /// Build fallback UI for empty/failed articles
  Widget _buildEmptyArticleFallback(BuildContext context, Article article) {
    final isTwitter = article.url.contains('twitter.com') || article.url.contains('x.com');

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.borderColor,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isTwitter ? Icons.lock_outline : Icons.article_outlined,
            size: 48,
            color: context.mutedTextColor,
          ),
          const SizedBox(height: 16),
          Text(
            isTwitter
                ? 'X/Twitter requires login to view'
                : 'Content could not be extracted',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isTwitter
                ? 'This post is behind a login wall. Tap below to open it in your browser or X app.'
                : 'This article couldn\'t be extracted automatically. Tap below to view it in your browser.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.mutedTextColor,
            ),
            textAlign: TextAlign.center,
          ),
          // Show description if available
          if (article.description != null && article.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                article.description!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(article.url),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_browser),
              label: Text(isTwitter ? 'Open in X / Browser' : 'Open in Browser'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: context.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<String> bullets,
    bool isExpanded = true,
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        final showAll = isExpanded;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: context.borderColor,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(icon, size: 18, color: context.primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Bullets
              ...bullets.map((bullet) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.mutedTextColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        bullet,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSourceLink(BuildContext context, Article article) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(article.url)),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.link,
              size: 18,
              color: context.primaryColor,
            ),
            const SizedBox(width: 8),
            Text(
              'Source: ',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.mutedTextColor,
              ),
            ),
            Expanded(
              child: Text(
                _extractDomain(article.url),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.primaryColor,
                  decoration: TextDecoration.underline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.open_in_new,
              size: 16,
              color: context.primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Article article) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete article?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(articleServiceProvider).delete(article.id);
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    return MarkdownStyleSheet(
      p: Theme.of(context).textTheme.bodyLarge,
      h1: Theme.of(context).textTheme.headlineLarge,
      h2: Theme.of(context).textTheme.headlineMedium,
      h3: Theme.of(context).textTheme.headlineSmall,
      h4: Theme.of(context).textTheme.titleLarge,
      h5: Theme.of(context).textTheme.titleMedium,
      h6: Theme.of(context).textTheme.titleSmall,
      blockquote: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontStyle: FontStyle.italic,
            color: context.mutedTextColor,
          ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: context.primaryColor,
            width: 4,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 16),
      code: TextStyle(
        fontFamily: 'monospace',
        backgroundColor: context.borderColor.withOpacity(0.5),
      ),
      codeblockDecoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.all(16),
      a: TextStyle(color: context.primaryColor),
      listBullet: Theme.of(context).textTheme.bodyLarge,
    );
  }
}

class _ImageAnalysesSection extends StatelessWidget {
  final List<ImageAnalysis> images;

  const _ImageAnalysesSection({required this.images});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.image_outlined, size: 20, color: context.primaryColor),
            const SizedBox(width: 8),
            Text(
              'Image Analysis',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...images.map((image) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: CachedNetworkImage(
                        imageUrl: image.imageUrl,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            image.description,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (image.relevance != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              image.relevance!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontStyle: FontStyle.italic,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}

class _CommentsSection extends StatelessWidget {
  final List<Comment> comments;
  final String? commentsSummary;

  const _CommentsSection({
    required this.comments,
    this.commentsSummary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.forum_outlined, size: 20, color: context.primaryColor),
            const SizedBox(width: 8),
            Text(
              'Discussion (${comments.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),

        // AI summary of comments
        if (commentsSummary != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.primaryColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: context.primaryColor.withOpacity(0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: context.primaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    commentsSummary!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Comments list
        ...comments.take(10).map((comment) => _CommentTile(comment: comment)),

        if (comments.length > 10)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '+ ${comments.length - 10} more comments',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.primaryColor,
                  ),
            ),
          ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final int depth;

  const _CommentTile({required this.comment, this.depth = 0});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                comment.author,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (comment.score != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.arrow_upward, size: 14, color: context.mutedTextColor),
                Text(
                  comment.score.toString(),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            comment.content,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (comment.replies.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...comment.replies
                .take(3)
                .map((reply) => _CommentTile(comment: reply, depth: depth + 1)),
          ],
        ],
      ),
    );
  }
}
