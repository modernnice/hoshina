import 'package:drama_tracker/models/anime_progress.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/services/local_notification_service.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CloudSyncService {
  CloudSyncService._();

  static final CloudSyncService instance = CloudSyncService._();

  SupabaseClient get _client => Supabase.instance.client;

  String? get _uid => _client.auth.currentUser?.id;

  Future<Map<String, dynamic>?> fetchProfile() async {
    final uid = _uid;
    if (uid == null) {
      return null;
    }
    final row = await _client.from('profiles').select().eq('id', uid).maybeSingle();
    return row;
  }

  Future<String?> updateNickname(String newNickname) async {
    final uid = _uid;
    if (uid == null) {
      return '未登录';
    }
    if (newNickname.trim().isEmpty) {
      return '昵称不能为空';
    }
    try {
      await _client.from('profiles').update({'nickname': newNickname.trim()}).eq('id', uid);
      return null;
    } catch (e) {
      return '修改昵称失败，请稍后重试';
    }
  }

  Future<List<Map<String, dynamic>>> fetchPreferences() async {
    final uid = _uid;
    if (uid == null) {
      return [];
    }
    final list = await _client
        .from('user_preferences')
        .select()
        .eq('user_uuid', uid)
        .order('updated_at', ascending: false);
    return List<Map<String, dynamic>>.from(list);
  }

  Future<void> syncSinglePreference(AnimeProgress item) async {
    final uid = _uid;
    if (uid == null) {
      return;
    }
    final payload = {
      'user_uuid': uid,
      'subject_id': item.subjectId,
      'status': item.status.name,
      'current_episode': item.currentEpisode,
      'total_episodes': item.totalEpisodes,
      'private_rating': item.privateRating,
      'private_review': item.privateReview,
      'reminder_enabled': item.reminderEnabled,
      'reminder_weekday': item.updateWeekday,
      'reminder_hour': item.reminderHour,
      'reminder_minute': item.reminderMinute,
      'updated_at': DateTime.now().toIso8601String(),
    };
    try {
      await _client.from('user_preferences').upsert([payload], onConflict: 'user_uuid,subject_id');
    } catch (e) {
      debugPrint('Cloud sync error (upsert): $e');
    }
  }

  Future<void> deleteSinglePreference(int subjectId) async {
    final uid = _uid;
    if (uid == null) {
      return;
    }
    try {
      await _client.from('user_preferences').delete().match({
        'user_uuid': uid,
        'subject_id': subjectId,
      });
    } catch (e) {
      debugPrint('Cloud sync error (delete): $e');
    }
  }

  Future<void> downloadToLocalPreferences(WatchlistStorage storage) async {
    final uid = _uid;
    if (uid == null) {
      return;
    }
    final rows = await fetchPreferences();
    final apiService = BangumiApiService();
    final remoteIds = <int>{};
    
    for (final row in rows) {
      final subjectId = int.tryParse((row['subject_id'] ?? 0).toString()) ?? 0;
      if (subjectId == 0) continue;
      remoteIds.add(subjectId);
      
      final existing = storage.getProgress(subjectId);
      String name = existing?.name ?? '';
      String coverUrl = existing?.coverUrl ?? '';
      
      // If metadata is missing (e.g., first login on a new device), fetch it from Bangumi API
      if (name.isEmpty || coverUrl.isEmpty) {
        try {
          final detail = await apiService.fetchSubjectDetail(subjectId);
          name = detail.name;
          coverUrl = detail.coverUrl;
        } catch (e) {
          debugPrint('Failed to fetch metadata for subject $subjectId: $e');
        }
      }

      final progress = AnimeProgress(
        subjectId: subjectId,
        name: name,
        coverUrl: coverUrl,
        currentEpisode: int.tryParse((row['current_episode'] ?? 0).toString()) ?? 0,
        totalEpisodes: int.tryParse((row['total_episodes'] ?? 0).toString()) ?? 0,
        status: _statusFromString(row['status']?.toString()),
        statusSelected: true,
        updateWeekday: int.tryParse((row['reminder_weekday'] ?? 0).toString()) ?? 0,
        privateRating: int.tryParse((row['private_rating'] ?? 0).toString()) ?? 0,
        privateReview: row['private_review']?.toString() ?? '',
        reminderEnabled: (row['reminder_enabled'] ?? false).toString() == 'true',
        reminderHour: int.tryParse((row['reminder_hour'] ?? 20).toString()) ?? 20,
        reminderMinute: int.tryParse((row['reminder_minute'] ?? 0).toString()) ?? 0,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      
      await storage.upsert(progress, syncToCloud: false);
    }

    final localItems = storage.getAllProgresses();
    for (final item in localItems) {
      if (remoteIds.contains(item.subjectId)) {
        continue;
      }
      await LocalNotificationService.instance.cancelReminder(item.subjectId);
      await storage.delete(item.subjectId, syncToCloud: false);
    }
  }

  WatchStatus _statusFromString(String? value) {
    for (final item in WatchStatus.values) {
      if (item.name == value) {
        return item;
      }
    }
    return WatchStatus.wish;
  }
}
