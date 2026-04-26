import 'dart:io';

import 'package:drama_tracker/models/anime_progress.dart';
import 'package:drama_tracker/services/watch_status_reminder_policy.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late Box<Map> watchlistBox;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('reminder_status_policy_test_');
    Hive.init(tempDir.path);
    watchlistBox = await Hive.openBox<Map>('watchlist');
  });

  tearDown(() async {
    await watchlistBox.clear();
  });

  tearDownAll(() async {
    await watchlistBox.close();
    await tempDir.delete(recursive: true);
  });

  test('watchlist storage disables reminders when status is not watching', () async {
    final storage = WatchlistStorage();

    await storage.upsert(
      AnimeProgress(
        subjectId: 1001,
        name: '测试番剧',
        coverUrl: '',
        currentEpisode: 3,
        totalEpisodes: 12,
        status: WatchStatus.finished,
        statusSelected: true,
        updateWeekday: 6,
        privateRating: 0,
        privateReview: '',
        reminderEnabled: true,
        reminderHour: 20,
        reminderMinute: 0,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      syncToCloud: false,
    );

    final saved = storage.getProgress(1001);
    expect(saved, isNotNull);
    expect(saved!.reminderEnabled, isFalse);
  });

  test('policy disables reminders when watch status is cleared', () {
    final normalized = WatchStatusReminderPolicy.normalize(
      AnimeProgress(
        subjectId: 1002,
        name: '测试番剧 2',
        coverUrl: '',
        currentEpisode: 1,
        totalEpisodes: 12,
        status: WatchStatus.watching,
        statusSelected: false,
        updateWeekday: 2,
        privateRating: 0,
        privateReview: '',
        reminderEnabled: true,
        reminderHour: 20,
        reminderMinute: 0,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    expect(normalized.reminderEnabled, isFalse);
  });

  test('storage repair clears legacy reminders for non-watching statuses', () async {
    await watchlistBox.put('1003', {
      'subjectId': 1003,
      'name': '旧数据番剧',
      'coverUrl': '',
      'currentEpisode': 10,
      'totalEpisodes': 12,
      'status': WatchStatus.finished.name,
      'statusSelected': true,
      'updateWeekday': 3,
      'privateRating': 0,
      'privateReview': '',
      'reminderEnabled': true,
      'reminderHour': 20,
      'reminderMinute': 0,
      'createdAtMs': 0,
    });

    final storage = WatchlistStorage();
    await storage.repairInvalidReminderStates(syncToCloud: false);

    final saved = storage.getProgress(1003);
    expect(saved, isNotNull);
    expect(saved!.reminderEnabled, isFalse);
    expect(saved.createdAtMs, greaterThan(0));
  });
}
