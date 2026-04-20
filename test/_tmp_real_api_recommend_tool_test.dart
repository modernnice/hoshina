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
    tempDir = await Directory.systemTemp.createTemp('real_api_recommend_test_');
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

  test('real bangumi api snapshot for slime and kanokari seeds', () async {
    final storage = WatchlistStorage();
    await storage.upsert(
      AnimeProgress(
        subjectId: 990001,
        name: '关于我转生变成史莱姆这档事 第四季',
        coverUrl: '',
        currentEpisode: 12,
        totalEpisodes: 24,
        status: WatchStatus.watching,
        statusSelected: true,
        updateWeekday: 5,
        privateRating: 8,
        privateReview: '异世界题材很喜欢',
        reminderEnabled: true,
        reminderHour: 20,
        reminderMinute: 0,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      syncToCloud: false,
    );
    await storage.upsert(
      AnimeProgress(
        subjectId: 990002,
        name: '租借女友',
        coverUrl: '',
        currentEpisode: 12,
        totalEpisodes: 12,
        status: WatchStatus.finished,
        statusSelected: true,
        updateWeekday: 6,
        privateRating: 8,
        privateReview: '恋爱题材也爱看',
        reminderEnabled: false,
        reminderHour: 20,
        reminderMinute: 0,
        createdAtMs: DateTime.now().millisecondsSinceEpoch - 1000,
      ),
      syncToCloud: false,
    );

    final tool = AnimeRecommendTool(BangumiApiService(), storage);
    final result = await tool.execute(<String, dynamic>{'count': 5});
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  }, timeout: const Timeout(Duration(seconds: 90)));
}
