import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/models/anime_progress.dart';
import 'package:drama_tracker/services/cloud_sync_service.dart';
import 'package:hive/hive.dart';

enum WatchStatus { wish, watching, finished }

class WatchlistStorage {
  WatchlistStorage() : _box = Hive.box<Map>('watchlist');

  final Box<Map> _box;

  String _key(int id) => id.toString();

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
    return AnimeProgress.fromMap(Map<String, dynamic>.from(value));
  }

  Future<void> upsert(AnimeProgress progress, {bool syncToCloud = true}) async {
    final existing = getProgress(progress.subjectId);
    final normalized = progress.copyWith(
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
        .map((item) => item.createdAtMs > 0
            ? item
            : item.copyWith(createdAtMs: DateTime.now().millisecondsSinceEpoch))
        .toList();
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
