import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class SupabaseService {
  SupabaseClient? _client;

  SupabaseService() {
    try {
      _client = Supabase.instance.client;
    } catch (e) {
      // Supabase not initialized - running in offline mode
      _client = null;
    }
  }

  bool get isInitialized => _client != null;
  SupabaseClient? get client => _client;
  String? get userId => _client?.auth.currentUser?.id;

  // ============ Articles ============

  /// Save a new article URL (processing happens via Edge Function)
  /// Returns the article (existing or newly created)
  /// Throws on critical errors (auth, network)
  ///
  /// If pre-extracted content is provided (from on-device authenticated extraction),
  /// it will be sent to the Edge Function for summarization without needing to re-fetch.
  Future<Article> saveArticle(
    String url, {
    String? preExtractedContent,
    String? preExtractedTitle,
    String? preExtractedImage,
    String? preExtractedAuthor,
  }) async {
    if (_client == null) {
      throw Exception('Supabase not initialized');
    }
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Normalize URL
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) {
      throw Exception('URL cannot be empty');
    }

    final hasPreExtracted = preExtractedContent != null && preExtractedContent.isNotEmpty;

    try {
      // Build insert data - if we have pre-extracted content, include it
      final insertData = <String, dynamic>{
        'user_id': userId,
        'url': normalizedUrl,
        'status': hasPreExtracted ? ArticleStatus.extracting.name : ArticleStatus.pending.name,
        'created_at': DateTime.now().toIso8601String(),
      };

      // If we have pre-extracted data, add it directly
      if (hasPreExtracted) {
        if (preExtractedTitle != null) insertData['title'] = preExtractedTitle;
        if (preExtractedImage != null) insertData['image_url'] = preExtractedImage;
        if (preExtractedAuthor != null) insertData['author'] = preExtractedAuthor;
        insertData['content'] = preExtractedContent;
      }

      // Try to insert the article
      final response = await _client!.from('articles').insert(insertData).select().single();

      final article = Article.fromJson(response);
      debugPrint('Article created: ${article.id}');

      // Trigger extraction via Edge Function
      _triggerExtraction(
        article.id,
        normalizedUrl,
        preExtractedContent: preExtractedContent,
        preExtractedTitle: preExtractedTitle,
        preExtractedImage: preExtractedImage,
        preExtractedAuthor: preExtractedAuthor,
      );

      return article;
    } catch (e) {
      // Check if this is a duplicate key error (unique constraint violation)
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('duplicate') ||
          errorMessage.contains('unique') ||
          errorMessage.contains('23505')) {
        debugPrint('Article already exists for URL: $normalizedUrl');

        // Return the existing article instead of failing
        final existing = await _client!
            .from('articles')
            .select()
            .eq('user_id', userId!)
            .eq('url', normalizedUrl)
            .maybeSingle();

        if (existing != null) {
          final article = Article.fromJson(existing);

          // If it's in a failed state, retry extraction
          if (article.status == ArticleStatus.failed) {
            debugPrint('Retrying extraction for failed article: ${article.id}');
            await _client!.from('articles').update({
              'status': ArticleStatus.pending.name,
            }).eq('id', article.id);
            _triggerExtraction(
              article.id,
              normalizedUrl,
              preExtractedContent: preExtractedContent,
              preExtractedTitle: preExtractedTitle,
              preExtractedImage: preExtractedImage,
              preExtractedAuthor: preExtractedAuthor,
            );
          }

          return article;
        }
      }

      // Re-throw other errors
      debugPrint('Error saving article: $e');
      rethrow;
    }
  }

  /// Trigger article extraction via Edge Function
  /// Errors are logged but don't block the caller
  ///
  /// If pre-extracted content is provided, the Edge Function will skip fetching
  /// and go straight to summarization.
  void _triggerExtraction(
    String articleId,
    String url, {
    String? preExtractedContent,
    String? preExtractedTitle,
    String? preExtractedImage,
    String? preExtractedAuthor,
  }) async {
    final hasPreExtracted = preExtractedContent != null && preExtractedContent.isNotEmpty;
    debugPrint('[EXTRACT] Starting extraction for article: $articleId');
    debugPrint('[EXTRACT] URL: $url, pre-extracted: $hasPreExtracted');

    // Early check for client
    if (_client == null) {
      debugPrint('[EXTRACT] ERROR: Supabase client is null!');
      return;
    }

    final body = <String, dynamic>{
      'article_id': articleId,
      'url': url,
    };

    // Add pre-extracted content if available
    if (hasPreExtracted) {
      body['pre_extracted'] = true;
      body['content'] = preExtractedContent;
      if (preExtractedTitle != null) body['title'] = preExtractedTitle;
      if (preExtractedImage != null) body['image_url'] = preExtractedImage;
      if (preExtractedAuthor != null) body['author'] = preExtractedAuthor;
    }

    try {
      debugPrint('[EXTRACT] Invoking edge function...');
      final response = await _client!.functions.invoke('extract-article', body: body);
      debugPrint('[EXTRACT] Function response status: ${response.status}');
      debugPrint('[EXTRACT] Function response data: ${response.data}');

      if (response.status >= 200 && response.status < 300) {
        debugPrint('[EXTRACT] Extraction triggered successfully for: $articleId');
      } else {
        debugPrint('[EXTRACT] Extraction failed with status ${response.status}');
        final errorMsg = 'Function error ${response.status}: ${response.data}'.toString();
        await _client!.from('articles').update({
          'status': ArticleStatus.failed.name,
          'description': errorMsg.length > 200 ? errorMsg.substring(0, 200) : errorMsg,
        }).eq('id', articleId);
      }
    } catch (error, stackTrace) {
      debugPrint('[EXTRACT] Exception during function invocation: $error');
      debugPrint('[EXTRACT] Stack trace: $stackTrace');

      // Mark article as failed with error details
      try {
        final errorMsg = 'Client error: ${error.toString()}';
        await _client!.from('articles').update({
          'status': ArticleStatus.failed.name,
          'description': errorMsg.length > 200 ? errorMsg.substring(0, 200) : errorMsg,
        }).eq('id', articleId);
        debugPrint('[EXTRACT] Marked article $articleId as failed');
      } catch (updateError) {
        debugPrint('[EXTRACT] Failed to update article status: $updateError');
      }
    }
  }

  /// Get all articles for current user
  Stream<List<Article>> watchArticles({bool includeArchived = false}) {
    if (_client == null || userId == null) {
      return Stream.value([]);
    }
    var query = _client!
        .from('articles')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId!)
        .order('created_at', ascending: false);

    return query.map((data) {
      final articles = data.map((e) => Article.fromJson(e)).toList();
      if (!includeArchived) {
        return articles.where((a) => !a.isArchived).toList();
      }
      return articles;
    });
  }

  /// Get single article by ID
  Future<Article> getArticle(String id) async {
    if (_client == null) {
      throw Exception('Supabase not initialized');
    }
    final response = await _client!
        .from('articles')
        .select()
        .eq('id', id)
        .single();
    return Article.fromJson(response);
  }

  /// Mark article as read
  Future<void> markAsRead(String id) async {
    if (_client == null) return;
    await _client!.from('articles').update({
      'read_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  /// Archive article
  Future<void> archiveArticle(String id) async {
    if (_client == null) return;
    await _client!.from('articles').update({
      'is_archived': true,
    }).eq('id', id);
  }

  /// Delete article
  Future<void> deleteArticle(String id) async {
    if (_client == null) return;
    await _client!.from('articles').delete().eq('id', id);
  }

  /// Get articles from a specific date (for digest)
  Future<List<Article>> getArticlesForDate(DateTime date) async {
    if (_client == null || userId == null) {
      return [];
    }
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final response = await _client!
        .from('articles')
        .select()
        .eq('user_id', userId!)
        .gte('created_at', startOfDay.toIso8601String())
        .lt('created_at', endOfDay.toIso8601String())
        .order('created_at', ascending: false);

    return (response as List).map((e) => Article.fromJson(e)).toList();
  }

  // ============ Digests ============

  /// Get all digests for current user
  Stream<List<DailyDigest>> watchDigests() {
    if (_client == null || userId == null) {
      return Stream.value([]);
    }
    return _client!
        .from('digests')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId!)
        .order('date', ascending: false)
        .map((data) => data.map((e) => DailyDigest.fromJson(e)).toList());
  }

  /// Get digest for a specific date
  Future<DailyDigest?> getDigestForDate(DateTime date) async {
    if (_client == null || userId == null) {
      return null;
    }
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    final response = await _client!
        .from('digests')
        .select()
        .eq('user_id', userId!)
        .eq('date', dateStr)
        .maybeSingle();

    if (response == null) return null;
    return DailyDigest.fromJson(response);
  }

  /// Get latest digest
  Future<DailyDigest?> getLatestDigest() async {
    if (_client == null || userId == null) {
      return null;
    }
    final response = await _client!
        .from('digests')
        .select()
        .eq('user_id', userId!)
        .order('date', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return DailyDigest.fromJson(response);
  }

  /// Mark digest as read
  Future<void> markDigestAsRead(String id) async {
    if (_client == null) return;
    await _client!.from('digests').update({
      'is_read': true,
    }).eq('id', id);
  }

  /// Manually trigger digest generation (for testing/on-demand)
  Future<DailyDigest?> generateDigest({DateTime? date}) async {
    if (_client == null) return null;
    final response = await _client!.functions.invoke('generate-digest', body: {
      'user_id': userId,
      'date': (date ?? DateTime.now()).toIso8601String(),
    });

    return DailyDigest.fromJson(response.data);
  }

  // ============ Auth ============

  Future<void> signInAnonymously() async {
    if (_client == null) return;
    await _client!.auth.signInAnonymously();
  }

  Future<void> signOut() async {
    if (_client == null) return;
    await _client!.auth.signOut();
  }

  Stream<AuthState>? get authStateChanges => _client?.auth.onAuthStateChange;

  // ============ User Settings ============

  Future<UserSettings> getUserSettings() async {
    if (_client == null || userId == null) throw Exception('Supabase not initialized');

    final response = await _client!.from('user_settings').select().eq('user_id', userId!).maybeSingle();

    if (response != null) return UserSettings.fromJson(response);

    // Create default settings if not exists
    final created = await _client!.from('user_settings').insert({
      'user_id': userId,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).select().single();
    return UserSettings.fromJson(created);
  }

  Future<UserSettings> updateSettings(UserSettings settings) async {
    if (_client == null || userId == null) throw Exception('Supabase not initialized');

    final response = await _client!.from('user_settings').update(settings.toJson()..['updated_at'] = DateTime.now().toIso8601String()).eq('user_id', userId!).select().single();
    return UserSettings.fromJson(response);
  }

  Stream<List<Article>> watchArchivedArticles() {
    if (_client == null || userId == null) return Stream.value([]);
    return _client!.from('articles').stream(primaryKey: ['id']).eq('user_id', userId!).order('created_at', ascending: false).map((data) => data.map((e) => Article.fromJson(e)).where((a) => a.isArchived).toList());
  }

  Future<void> unarchiveArticle(String id) async {
    if (_client == null) return;
    await _client!.from('articles').update({'is_archived': false}).eq('id', id);
  }

  Future<void> clearAllData() async {
    if (_client == null || userId == null) return;
    await _client!.from('articles').delete().eq('user_id', userId!);
    await _client!.from('digests').delete().eq('user_id', userId!);
  }

  Future<Map<String, dynamic>> exportUserData() async {
    if (_client == null || userId == null) throw Exception('Supabase not initialized');
    final articles = await _client!.from('articles').select().eq('user_id', userId!);
    final digests = await _client!.from('digests').select().eq('user_id', userId!);
    return {'exported_at': DateTime.now().toIso8601String(), 'articles': articles, 'digests': digests};
  }
}
