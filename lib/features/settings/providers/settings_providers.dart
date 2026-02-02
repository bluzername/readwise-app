import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/models.dart';
import '../../../core/services/supabase_service.dart';
import '../../articles/providers/article_providers.dart';

class SettingsNotifier extends AsyncNotifier<UserSettings> {
  @override
  Future<UserSettings> build() => ref.read(supabaseServiceProvider).getUserSettings();

  Future<void> updateDigestTime(TimeOfDay time) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(supabaseServiceProvider).updateSettings(current.copyWith(digestTime: time)));
  }

  Future<void> toggleAnalyzeImages(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(supabaseServiceProvider).updateSettings(current.copyWith(analyzeImages: value)));
  }

  Future<void> toggleIncludeComments(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(supabaseServiceProvider).updateSettings(current.copyWith(includeComments: value)));
  }

  Future<void> togglePushNotifications(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(supabaseServiceProvider).updateSettings(current.copyWith(pushNotifications: value)));
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, UserSettings>(SettingsNotifier.new);

final archivedArticlesProvider = StreamProvider<List<Article>>((ref) => ref.read(supabaseServiceProvider).watchArchivedArticles());

class DataService {
  final SupabaseService _supabase;
  DataService(this._supabase);

  Future<void> clearAllData() => _supabase.clearAllData();
  Future<void> unarchiveArticle(String id) => _supabase.unarchiveArticle(id);

  Future<void> exportAndShare() async {
    final data = await _supabase.exportUserData();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/readzero_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(json);
    await Share.shareXFiles([XFile(file.path)], subject: 'ReadZero Data Export');
  }
}

final dataServiceProvider = Provider((ref) => DataService(ref.read(supabaseServiceProvider)));
