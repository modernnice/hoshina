import 'dart:io';

import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/models/anime_detail.dart';
import 'package:drama_tracker/models/anime_progress.dart';
import 'package:drama_tracker/services/agent/anime_search_tool.dart';
import 'package:drama_tracker/services/agent/get_user_preference_seeds_tool.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late Box<Map> watchlistBox;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('anime_recommend_tool_test_');
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

  test('search anime by tags filters watched franchises and keeps new series',
      () async {
    final storage = WatchlistStorage();
    await storage.upsert(
      AnimeProgress(
        subjectId: 900001,
        name: '加油吧！中村君！！',
        coverUrl: '',
        currentEpisode: 12,
        totalEpisodes: 12,
        status: WatchStatus.finished,
        statusSelected: true,
        updateWeekday: 6,
        privateRating: 9,
        privateReview: '恋爱喜剧很对胃口',
        reminderEnabled: false,
        reminderHour: 20,
        reminderMinute: 0,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      syncToCloud: false,
    );
    await storage.upsert(
      AnimeProgress(
        subjectId: 900002,
        name: '租借女友 第二季',
        coverUrl: '',
        currentEpisode: 12,
        totalEpisodes: 12,
        status: WatchStatus.finished,
        statusSelected: true,
        updateWeekday: 5,
        privateRating: 8,
        privateReview: '恋爱题材也想继续补',
        reminderEnabled: false,
        reminderHour: 20,
        reminderMinute: 0,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      syncToCloud: false,
    );

    final api = _FakeBangumiApiService();
    final tool = AnimeSearchTool(api, storage);

    final result = await tool.execute({
      'tags': ['恋爱', '校园'],
      'limit': 8,
      'sort': 'heat',
      'excludeWatched': true,
      'excludeSameSeries': true,
      'recommendationMode': true,
    });

    expect(result.success, isTrue);
    expect(result.items.map((item) => item.id), isNot(contains(451644)));
    expect(result.items.map((item) => item.id), isNot(contains(452702)));
    expect(result.items.map((item) => item.id), isNot(contains(452706)));
    expect(result.items.map((item) => item.id), contains(551001));
    expect(
      (result.payload['request'] as Map<String, dynamic>)['filter']['tag'],
      equals(<String>['恋爱', '校园']),
    );
    expect(result.payload['excludeWatched'], isTrue);
    expect(result.payload['excludeSameSeries'], isTrue);
    expect(result.payload['recommendationMode'], isTrue);
    expect(
      api.calls.any(
        (call) =>
            call.keyword.isEmpty &&
            call.tags.length == 2 &&
            call.tags.contains('恋爱') &&
            call.tags.contains('校园'),
      ),
      isTrue,
    );
  });

  test('get user preference seeds returns more than four distinct series seeds',
      () async {
    final storage = WatchlistStorage();
    const names = <String>[
      '海边的恋人',
      '星空列车',
      '白昼流星',
      '玻璃花房',
      '雨后信箱',
      '远山乐队',
    ];
    for (var i = 0; i < names.length; i++) {
      await storage.upsert(
        AnimeProgress(
          subjectId: 910000 + i,
          name: names[i],
          coverUrl: '',
          currentEpisode: 12,
          totalEpisodes: 12,
          status: WatchStatus.finished,
          statusSelected: true,
          updateWeekday: i,
          privateRating: 9 - i,
          privateReview: '',
          reminderEnabled: false,
          reminderHour: 20,
          reminderMinute: 0,
          createdAtMs: DateTime.now().millisecondsSinceEpoch - (i * 1000),
        ),
        syncToCloud: false,
      );
    }

    final api = _FakeBangumiApiService();
    final tool = GetUserPreferenceSeedsTool(api, storage);

    final result = await tool.execute(const <String, dynamic>{});
    final seeds =
        (result.payload['seeds'] as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>();

    expect(result.success, isTrue);
    expect(seeds.length, greaterThan(4));
    expect(
      seeds.map((seed) => seed['name']).toList(),
      containsAll(<String>[
        '海边的恋人',
        '星空列车',
        '白昼流星',
        '玻璃花房',
        '雨后信箱',
      ]),
    );
  });

  test(
      'get user preference seeds prefers bangumi official tags over plain text matching',
      () async {
    final storage = WatchlistStorage();
    await storage.upsert(
      AnimeProgress(
        subjectId: 920001,
        name: '官方标签测试作品',
        coverUrl: '',
        currentEpisode: 12,
        totalEpisodes: 12,
        status: WatchStatus.finished,
        statusSelected: true,
        updateWeekday: 1,
        privateRating: 9,
        privateReview: '这条短评故意不写关键词',
        reminderEnabled: false,
        reminderHour: 20,
        reminderMinute: 0,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      syncToCloud: false,
    );

    final api = _FakeBangumiApiService();
    final tool = GetUserPreferenceSeedsTool(api, storage);

    final result = await tool.execute(const <String, dynamic>{});
    final preferenceTags =
        (result.payload['all_preference_tags'] as List<dynamic>? ??
                const <dynamic>[])
            .map((item) => item.toString())
            .toList();
    final firstSeed =
        ((result.payload['seeds'] as List<dynamic>? ?? const <dynamic>[])
                .cast<Map<String, dynamic>>())
            .first;

    expect(result.success, isTrue);
    expect(preferenceTags, contains('恋爱'));
    expect(preferenceTags, contains('异世界'));
    expect(firstSeed['tags'], containsAll(<String>['恋爱', '异世界']));
  });
}

class _FakeBangumiApiService extends BangumiApiService {
  final List<_SearchCall> calls = <_SearchCall>[];

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
    calls.add(_SearchCall(keyword: keyword, tags: tags, sort: sort));
    if (tags.length == 2 && tags.contains('恋爱') && tags.contains('校园')) {
      return AnimeSearchPage(
        total: 4,
        limit: limit,
        offset: offset,
        data: <AnimeCalendarItem>[
          _item(id: 451644, name: '租借女友 第三季', rating: 7.2, doing: 120),
          _item(id: 452702, name: '租借女友 小剧场', rating: 5.5, doing: 2),
          _item(id: 452706, name: '租借女友 小剧场 第二季', rating: 5.2, doing: 3),
          _item(id: 551001, name: '堀与宫村', rating: 7.9, doing: 980),
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

  @override
  Future<AnimeDetail> fetchSubjectDetail(int id) async {
    if (id == 900001) {
      return _detail(id, '加油吧！中村君！！', tags: const <String>['恋爱', '校园']);
    }
    if (id == 900002) {
      return _detail(id, '租借女友 第二季', tags: const <String>['恋爱']);
    }
    if (id == 920001) {
      return _detail(id, '官方标签测试作品', tags: const <String>['恋爱', '异世界']);
    }
    if (id >= 910000 && id <= 910005) {
      return _detail(id, 'seed-$id', tags: const <String>['恋爱', '校园']);
    }
    throw Exception('not mocked');
  }

  AnimeDetail _detail(
    int id,
    String name, {
    required List<String> tags,
  }) {
    return AnimeDetail(
      id: id,
      name: name,
      originName: name,
      coverUrl: '',
      summary: 'summary',
      totalEpisodes: 12,
      airWeekday: 1,
      airDate: '2024-01-01',
      date: '2024-01-01',
      platform: 'TV',
      ratingScore: 7.5,
      ratingRank: 100,
      ratingTotal: 1000,
      tags: tags,
      metaTags: const <String>['漫画改'],
      infobox: const <AnimeInfoboxItem>[],
      collectionWish: 0,
      collectionDoing: 0,
      collectionCollect: 0,
      collectionOnHold: 0,
      collectionDropped: 0,
    );
  }

  AnimeCalendarItem _item({
    required int id,
    required String name,
    required double rating,
    required int doing,
  }) {
    return AnimeCalendarItem(
      id: id,
      name: name,
      coverUrl: '',
      airWeekday: 0,
      airDate: '2024-01-01',
      ratingScore: rating,
      doingCount: doing,
    );
  }
}

class _SearchCall {
  const _SearchCall({
    required this.keyword,
    required this.tags,
    required this.sort,
  });

  final String keyword;
  final List<String> tags;
  final String sort;
}
