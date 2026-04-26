import 'dart:io';

import 'package:drama_tracker/models/anime_progress.dart';
import 'package:drama_tracker/services/agent/anime_control_tool.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notificationsChannel = MethodChannel('dexterous.com/flutter/local_notifications');

  late Directory tempDir;
  late Box<Map> watchlistBox;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
      return null;
    });
    tempDir = await Directory.systemTemp.createTemp('anime_control_tool_test_');
    Hive.init(tempDir.path);
    watchlistBox = await Hive.openBox<Map>('watchlist');
  });

  tearDown(() async {
    await watchlistBox.clear();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
    await watchlistBox.close();
    await tempDir.delete(recursive: true);
  });

  test('agent turns reminder off when marking anime as wish', () async {
    final storage = WatchlistStorage();
    await storage.upsert(
      AnimeProgress(
        subjectId: 2001,
        name: '番剧 A',
        coverUrl: '',
        currentEpisode: 3,
        totalEpisodes: 12,
        status: WatchStatus.watching,
        statusSelected: true,
        updateWeekday: 5,
        privateRating: 0,
        privateReview: '',
        reminderEnabled: true,
        reminderHour: 20,
        reminderMinute: 0,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      syncToCloud: false,
    );

    final tool = AnimeControlTool(storage, BangumiApiService());
    final result = await tool.execute({
      'intent': 'MARK_WANT_TO_WATCH',
      'animeId': 2001,
    });

    expect(result.success, isTrue);
    expect(storage.getProgress(2001)?.status, WatchStatus.wish);
    expect(storage.getProgress(2001)?.reminderEnabled, isFalse);
  });

  test('agent refuses to enable reminder when anime is not watching', () async {
    final storage = WatchlistStorage();
    await storage.upsert(
      AnimeProgress(
        subjectId: 2002,
        name: '番剧 B',
        coverUrl: '',
        currentEpisode: 0,
        totalEpisodes: 12,
        status: WatchStatus.wish,
        statusSelected: true,
        updateWeekday: 4,
        privateRating: 0,
        privateReview: '',
        reminderEnabled: false,
        reminderHour: 20,
        reminderMinute: 0,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      syncToCloud: false,
    );

    final tool = AnimeControlTool(storage, BangumiApiService());
    final result = await tool.execute({
      'intent': 'TOGGLE_REMIND',
      'animeId': 2002,
      'remindOn': true,
    });

    expect(result.success, isFalse);
    expect(result.message, contains('只有标记为在看时才能开启提醒'));
    expect(storage.getProgress(2002)?.reminderEnabled, isFalse);
  });
}
