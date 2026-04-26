import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/models/anime_progress.dart';
import 'package:drama_tracker/services/cloud_sync_service.dart';
import 'package:drama_tracker/services/watch_status_reminder_policy.dart';
import 'package:hive/hive.dart';

enum WatchStatus { wish, watching, finished }

class WatchlistStorage {
  WatchlistStorage() : _box = Hive.box<Map>('watchlist');

  final Box<Map> _box;

  String _key(int id) => id.toString();

  AnimeProgress _normalizeLoadedProgress(AnimeProgress progress) {
    final normalized = WatchStatusReminderPolicy.normalize(progress);
    if (normalized.createdAtMs > 0) {
      return normalized;
    }
    return normalized.copyWith(createdAtMs: DateTime.now().millisecondsSinceEpoch);
  }

  bool _needsRepair(AnimeProgress raw, AnimeProgress normalized) {
    return raw.reminderEnabled != normalized.reminderEnabled ||
        raw.createdAtMs != normalized.createdAtMs;
  }

  Future<void> save(AnimeCalendarItem item, WatchStatus status) async {
    final existing = getProgress(item.id);
    final progress = (existing ??
            AnimeProgress(
              subjectId: item.id,
              name: item.name,
              coverUrl: item.coverUrl,
              currentEpisode: 0,
              totalEpisodes: 0,
              status: status,
              statusSelected: true,
              updateWeekday: item.airWeekday,
              privateRating: 0,
              privateReview: '',
              reminderEnabled: false,
              reminderHour: 20,
              reminderMinute: 0,
              createdAtMs: DateTime.now().millisecondsSinceEpoch,
            ))
        .copyWith(
      name: item.name,
      coverUrl: item.coverUrl,
      updateWeekday: item.airWeekday,
      status: status,
      statusSelected: true,
    );
    await upsert(progress);
  }

  WatchStatus? getStatus(int id) {
    final progress = getProgress(id);
    if (progress == null || !progress.statusSelected) {
      return null;
    }
    return progress.status;
  }

  AnimeProgress? getProgress(int subjectId) {
    final value = _box.get(_key(subjectId));
    if (value == null) {
      return null;
    }
    return _normalizeLoadedProgress(
      AnimeProgress.fromMap(Map<String, dynamic>.from(value)),
    );
  }

  Future<void> upsert(AnimeProgress progress, {bool syncToCloud = true}) async {
    final existing = getProgress(progress.subjectId);
    final normalized = WatchStatusReminderPolicy.normalize(progress).copyWith(
      createdAtMs: existing?.createdAtMs ?? (progress.createdAtMs > 0 ? progress.createdAtMs : DateTime.now().millisecondsSinceEpoch),
    );
    await _box.put(_key(progress.subjectId), normalized.toMap());
    if (syncToCloud) {
      CloudSyncService.instance.syncSinglePreference(normalized);
    }
  }

  List<AnimeProgress> getAllProgresses() {
    return _box.values
        .whereType<Map>()
        .map((map) => AnimeProgress.fromMap(Map<String, dynamic>.from(map)))
        .map(_normalizeLoadedProgress)
        .toList();
  }

  Future<void> repairInvalidReminderStates({bool syncToCloud = false}) async {
    final snapshots = _box.values
        .whereType<Map>()
        .map((map) => AnimeProgress.fromMap(Map<String, dynamic>.from(map)))
        .toList();
    for (final raw in snapshots) {
      final normalized = _normalizeLoadedProgress(raw);
      if (!_needsRepair(raw, normalized)) {
        continue;
      }
      await _box.put(_key(normalized.subjectId), normalized.toMap());
      if (syncToCloud) {
        CloudSyncService.instance.syncSinglePreference(normalized);
      }
    }
  }

  List<AnimeProgress> getByStatus(WatchStatus status) {
    final all = getAllProgresses();
    all.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return all.where((item) => item.statusSelected && item.status == status).toList();
  }

  Future<void> delete(int subjectId, {bool syncToCloud = true}) async {
    await _box.delete(_key(subjectId));
    if (syncToCloud) {
      CloudSyncService.instance.deleteSinglePreference(subjectId);
    }
  }
}
