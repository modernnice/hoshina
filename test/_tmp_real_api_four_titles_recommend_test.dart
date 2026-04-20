import 'dart:convert';
import 'dart:io';

import 'package:drama_tracker/models/anime_progress.dart';
import 'package:drama_tracker/services/agent/anime_recommend_tool.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late Box<Map> watchlistBox;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('real_api_four_titles_test_');
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

  test('real bangumi api snapshot for grand blue kaguya aobuta mygo seeds', () async {
    final storage = WatchlistStorage();
    final now = DateTime.now().millisecondsSinceEpoch;

    await storage.upsert(
      AnimeProgress(
        subjectId: 235130,
        name: '碧蓝之海',
        coverUrl: '',
        currentEpisode: 12,
        totalEpisodes: 12,
        status: WatchStatus.finished,
        statusSelected: true,
        updateWeekday: 6,
        privateRating: 9,
        privateReview: '',
        reminderEnabled: false,
        reminderHour: 20,
        reminderMinute: 0,
        createdAtMs: now,
      ),
      syncToCloud: false,
    );

    await storage.upsert(
      AnimeProgress(
        subjectId: 248175,
        name: '辉夜大小姐想让我告白～天才们的恋爱头脑战～',
        coverUrl: '',
        currentEpisode: 12,
        totalEpisodes: 12,
        status: WatchStatus.finished,
        statusSelected: true,
        updateWeekday: 5,
        privateRating: 9,
        privateReview: '',
        reminderEnabled: false,
        reminderHour: 20,
        reminderMinute: 0,
        createdAtMs: now - 1000,
      ),
      syncToCloud: false,
    );

    await storage.upsert(
      AnimeProgress(
        subjectId: 240038,
        name: '青春猪头少年不会梦到兔女郎学姐',
        coverUrl: '',
        currentEpisode: 13,
        totalEpisodes: 13,
        status: WatchStatus.finished,
        statusSelected: true,
        updateWeekday: 4,
        privateRating: 8,
        privateReview: '',
        reminderEnabled: false,
        reminderHour: 20,
        reminderMinute: 0,
        createdAtMs: now - 2000,
      ),
      syncToCloud: false,
    );

    await storage.upsert(
      AnimeProgress(
        subjectId: 428735,
        name: 'BanG Dream! It\'s MyGO!!!!!',
        coverUrl: '',
        currentEpisode: 13,
        totalEpisodes: 13,
        status: WatchStatus.finished,
        statusSelected: true,
        updateWeekday: 3,
        privateRating: 9,
        privateReview: '',
        reminderEnabled: true,
        reminderHour: 20,
        reminderMinute: 0,
        createdAtMs: now - 3000,
      ),
      syncToCloud: false,
    );

    final tool = AnimeRecommendTool(BangumiApiService(), storage);
    final result = await tool.execute(<String, dynamic>{'count': 5});
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  }, timeout: const Timeout(Duration(seconds: 120)));
}
