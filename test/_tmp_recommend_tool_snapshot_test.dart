import 'dart:convert';
import 'dart:io';

import 'package:drama_tracker/models/anime_calendar_item.dart';
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
    tempDir = await Directory.systemTemp.createTemp('recommend_snapshot_test_');
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

  test('snapshot tool output for slime and kanokari seeds', () async {
    final storage = WatchlistStorage();
    await storage.upsert(
      AnimeProgress(
        subjectId: 900201,
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
        subjectId: 900202,
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

    final tool = AnimeRecommendTool(_SnapshotBangumiApiService(), storage);
    final result = await tool.execute(<String, dynamic>{'count': 5});
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  });
}

class _SnapshotBangumiApiService extends BangumiApiService {
  @override
  Future<AnimeSearchPage> searchSubjects({
    required String keyword,
    int limit = 20,
    int offset = 0,
    String sort = 'rank',
    List<String> tags = const [],
    List<String> metaTags = const [],
    List<String> airDate = const [],
    List<String> rating = const [],
    List<String> ratingCount = const [],
    List<String> rank = const [],
    bool? nsfw,
  }) async {
    if (keyword == '关于我转生变成史莱姆这档事 第四季') {
      return AnimeSearchPage(
        total: 4,
        limit: limit,
        offset: offset,
        data: <AnimeCalendarItem>[
          _item(302523, '关于我转生变成史莱姆这档事 第二季 第2部分', 6.1, 545),
          _item(421174, '关于我转生变成史莱姆这档事 柯里乌斯之梦', 5.9, 136),
          _item(520588, '关于我转生变成史莱姆这档事 魔王与龙的建国谭 3周年纪念新动画PV', 5.6, 10),
          _item(400602, '葬送的芙莉莲', 8.5, 11595),
        ],
      );
    }
    if (keyword == '租借女友') {
      return AnimeSearchPage(
        total: 2,
        limit: limit,
        offset: offset,
        data: <AnimeCalendarItem>[
          _item(451644, '租借女友 第三季', 7.2, 120),
          _item(214272, '欢迎来到实力至上主义的教室', 6.2, 723),
        ],
      );
    }
    if (tags.length == 1 && tags.first == '异世界') {
      return AnimeSearchPage(
        total: 2,
        limit: limit,
        offset: offset,
        data: <AnimeCalendarItem>[
          _item(400602, '葬送的芙莉莲', 8.5, 11595),
          _item(277554, '无职转生', 7.9, 6400),
        ],
      );
    }
    if (tags.length == 1 && tags.first == '恋爱') {
      return AnimeSearchPage(
        total: 2,
        limit: limit,
        offset: offset,
        data: <AnimeCalendarItem>[
          _item(214272, '欢迎来到实力至上主义的教室', 6.2, 723),
          _item(551001, '堀与宫村', 7.9, 980),
        ],
      );
    }
    return AnimeSearchPage(
      total: 0,
      limit: limit,
      offset: offset,
      data: const <AnimeCalendarItem>[],
    );
  }

  AnimeCalendarItem _item(int id, String name, double score, int doingCount) {
    return AnimeCalendarItem(
      id: id,
      name: name,
      coverUrl: '',
      airWeekday: 0,
      airDate: '2024-01-01',
      ratingScore: score,
      doingCount: doingCount,
    );
  }
}
