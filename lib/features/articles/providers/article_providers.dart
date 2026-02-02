import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/models/models.dart';

/// Supabase service provider
final supabaseServiceProvider = Provider((ref) => SupabaseService());

/// Article service provider with convenience methods
final articleServiceProvider = Provider((ref) {
  return ArticleService(ref.read(supabaseServiceProvider));
});

class ArticleService {
  final SupabaseService _supabase;

  ArticleService(this._supabase);

  Future<Article> saveArticle({
    required String url,
    String? preExtractedContent,
    String? preExtractedTitle,
    String? preExtractedImage,
    String? preExtractedAuthor,
  }) {
    return _supabase.saveArticle(
      url,
      preExtractedContent: preExtractedContent,
      preExtractedTitle: preExtractedTitle,
      preExtractedImage: preExtractedImage,
      preExtractedAuthor: preExtractedAuthor,
    );
  }

  Future<void> markAsRead(String id) => _supabase.markAsRead(id);
  Future<void> archive(String id) => _supabase.archiveArticle(id);
  Future<void> delete(String id) => _supabase.deleteArticle(id);
}

/// Stream of all articles
final articlesStreamProvider = StreamProvider<List<Article>>((ref) {
  return ref.read(supabaseServiceProvider).watchArticles();
});

/// Single article by ID
final articleProvider = FutureProvider.family<Article, String>((ref, id) {
  return ref.read(supabaseServiceProvider).getArticle(id);
});

/// Articles grouped by date for display
final articlesByDateProvider = Provider<Map<DateTime, List<Article>>>((ref) {
  final articlesAsync = ref.watch(articlesStreamProvider);
  
  return articlesAsync.when(
    data: (articles) {
      final grouped = <DateTime, List<Article>>{};
      for (final article in articles) {
        final date = DateTime(
          article.createdAt.year,
          article.createdAt.month,
          article.createdAt.day,
        );
        grouped.putIfAbsent(date, () => []).add(article);
      }
      return grouped;
    },
    loading: () => {},
    error: (_, __) => {},
  );
});

/// Stream of digests
final digestsStreamProvider = StreamProvider<List<DailyDigest>>((ref) {
  return ref.read(supabaseServiceProvider).watchDigests();
});

/// Latest digest
final latestDigestProvider = FutureProvider<DailyDigest?>((ref) {
  return ref.read(supabaseServiceProvider).getLatestDigest();
});

/// Digest for specific date
final digestForDateProvider = FutureProvider.family<DailyDigest?, DateTime>((ref, date) {
  return ref.read(supabaseServiceProvider).getDigestForDate(date);
});

/// Pending articles count (for badges)
final pendingArticlesCountProvider = Provider<int>((ref) {
  final articlesAsync = ref.watch(articlesStreamProvider);
  return articlesAsync.when(
    data: (articles) => articles.where((a) => a.status == ArticleStatus.pending || a.status == ArticleStatus.extracting).length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});

/// Unread articles count
final unreadArticlesCountProvider = Provider<int>((ref) {
  final articlesAsync = ref.watch(articlesStreamProvider);
  return articlesAsync.when(
    data: (articles) => articles.where((a) => a.readAt == null && a.status == ArticleStatus.ready).length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});
