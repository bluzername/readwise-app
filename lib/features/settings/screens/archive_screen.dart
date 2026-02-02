import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/settings_providers.dart';

class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedAsync = ref.watch(archivedArticlesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Archived Articles'),
      ),
      body: archivedAsync.when(
        data: (articles) {
          if (articles.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.archive_outlined,
                    size: 64,
                    color: context.mutedTextColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No archived articles',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: context.mutedTextColor,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Articles you archive will appear here',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.mutedTextColor,
                        ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: articles.length,
            itemBuilder: (context, index) {
              final article = articles[index];
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: article.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: article.imageUrl!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: 56,
                            height: 56,
                            color: context.mutedTextColor.withOpacity(0.1),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: 56,
                            height: 56,
                            color: context.mutedTextColor.withOpacity(0.1),
                            child: Icon(
                              Icons.article_outlined,
                              color: context.mutedTextColor,
                            ),
                          ),
                        )
                      : Container(
                          width: 56,
                          height: 56,
                          color: context.mutedTextColor.withOpacity(0.1),
                          child: Icon(
                            Icons.article_outlined,
                            color: context.mutedTextColor,
                          ),
                        ),
                ),
                title: Text(
                  article.title ?? article.url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: article.siteName != null
                    ? Text(
                        article.siteName!,
                        style: TextStyle(color: context.mutedTextColor),
                      )
                    : null,
                trailing: IconButton(
                  icon: const Icon(Icons.unarchive_outlined),
                  tooltip: 'Unarchive',
                  onPressed: () async {
                    await ref.read(dataServiceProvider).unarchiveArticle(article.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Article unarchived'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
                onTap: () => context.push('/article/${article.id}'),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: context.mutedTextColor,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load archived articles',
                style: TextStyle(color: context.mutedTextColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
