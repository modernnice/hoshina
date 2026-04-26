import 'package:drama_tracker/models/anime_progress.dart';
import 'package:drama_tracker/services/auth_service.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/services/local_notification_service.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CloudSyncService {
  CloudSyncService._();

  static final CloudSyncService instance = CloudSyncService._();

  SupabaseClient? get _clientOrNull {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  String? get _uid => _clientOrNull?.auth.currentUser?.id;

  bool _isAuthExpiredError(Object error) {
    if (error is AuthException) {
      return error.statusCode == '401' || error.message.toLowerCase().contains('jwt');
    }
    if (error is PostgrestException) {
      final code = error.code?.toUpperCase() ?? '';
      final message = error.message.toLowerCase();
      return code == 'PGRST303' || message.contains('jwt expired') || message.contains('unauthorized');
    }
    return false;
  }

  Future<void> _logoutExpiredSession(Object error) async {
    if (!_isAuthExpiredError(error)) {
      return;
    }
    debugPrint('Cloud sync session expired, signing out locally: $error');
    await AuthService.instance.logout();
  }

  Future<Map<String, dynamic>?> fetchProfile() async {
    final ready = await AuthService.instance.ensureValidSession();
    final uid = _uid;
    final client = _clientOrNull;
    if (!ready || uid == null || client == null) {
      return null;
    }
    try {
      final row = await client.from('profiles').select().eq('id', uid).maybeSingle();
      return row;
    } on AuthException catch (e) {
      await _logoutExpiredSession(e);
      return null;
    } on PostgrestException catch (e) {
      await _logoutExpiredSession(e);
      return null;
    }
  }

  Future<String?> updateNickname(String newNickname) async {
    final ready = await AuthService.instance.ensureValidSession();
    final uid = _uid;
    final client = _clientOrNull;
    if (!ready || uid == null || client == null) {
      return '未登录';
    }
    if (newNickname.trim().isEmpty) {
      return '昵称不能为空';
    }
    try {
      await client.from('profiles').update({'nickname': newNickname.trim()}).eq('id', uid);
      return null;
    } on AuthException catch (e) {
      await _logoutExpiredSession(e);
      return '登录已过期，请重新登录';
    } on PostgrestException catch (e) {
      await _logoutExpiredSession(e);
      return '登录已过期，请重新登录';
    } catch (e) {
      return '修改昵称失败，请稍后重试';
    }
  }

  Future<List<Map<String, dynamic>>> fetchPreferences() async {
    final ready = await AuthService.instance.ensureValidSession();
    final uid = _uid;
    final client = _clientOrNull;
    if (!ready || uid == null || client == null) {
      return [];
    }
    try {
      final list = await client
          .from('user_preferences')
          .select()
          .eq('user_uuid', uid)
          .order('updated_at', ascending: false);
      return List<Map<String, dynamic>>.from(list);
    } on AuthException catch (e) {
      await _logoutExpiredSession(e);
      return [];
    } on PostgrestException catch (e) {
      await _logoutExpiredSession(e);
      return [];
    }
  }

  Future<void> syncSinglePreference(AnimeProgress item) async {
    final ready = await AuthService.instance.ensureValidSession();
    final uid = _uid;
    final client = _clientOrNull;
    if (!ready || uid == null || client == null) {
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
      await client.from('user_preferences').upsert([payload], onConflict: 'user_uuid,subject_id');
    } on AuthException catch (e) {
      await _logoutExpiredSession(e);
    } on PostgrestException catch (e) {
      await _logoutExpiredSession(e);
    } catch (e) {
      debugPrint('Cloud sync error (upsert): $e');
    }
  }

  Future<void> deleteSinglePreference(int subjectId) async {
    final ready = await AuthService.instance.ensureValidSession();
    final uid = _uid;
    final client = _clientOrNull;
    if (!ready || uid == null || client == null) {
      return;
    }
    try {
      await client.from('user_preferences').delete().match({
        'user_uuid': uid,
        'subject_id': subjectId,
      });
    } on AuthException catch (e) {
      await _logoutExpiredSession(e);
    } on PostgrestException catch (e) {
      await _logoutExpiredSession(e);
    } catch (e) {
      debugPrint('Cloud sync error (delete): $e');
    }
  }

  Future<void> downloadToLocalPreferences(WatchlistStorage storage) async {
    final ready = await AuthService.instance.ensureValidSession();
    final uid = _uid;
    final client = _clientOrNull;
    if (!ready || uid == null || client == null) {
      return;
    }
    List<Map<String, dynamic>> rows;
    try {
      final rawRows = await client
          .from('user_preferences')
          .select()
          .eq('user_uuid', uid)
          .order('updated_at', ascending: false);
      rows = List<Map<String, dynamic>>.from(rawRows);
    } on AuthException catch (e) {
      await _logoutExpiredSession(e);
      return;
    } on PostgrestException catch (e) {
      await _logoutExpiredSession(e);
      return;
    }
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
