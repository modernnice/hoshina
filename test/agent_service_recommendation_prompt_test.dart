import 'dart:convert';
import 'dart:io';

import 'package:drama_tracker/models/agent_message.dart';
import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/models/anime_detail.dart';
import 'package:drama_tracker/models/anime_progress.dart';
import 'package:drama_tracker/models/llm_config.dart';
import 'package:drama_tracker/services/agent/agent_service.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/services/llm_api_service.dart';
import 'package:drama_tracker/services/llm_config_storage.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late Box<Map> watchlistBox;
  late Box<Map> configBox;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('agent_service_test_');
    Hive.init(tempDir.path);
    watchlistBox = await Hive.openBox<Map>('watchlist');
    configBox = await Hive.openBox<Map>('llm_config_box');
  });

  tearDown(() async {
    await watchlistBox.clear();
    await configBox.clear();
  });

  tearDownAll(() async {
    await watchlistBox.close();
    await configBox.close();
    await tempDir.delete(recursive: true);
  });

  test(
      'agent uses preference seeds then diversified tag searches for recommendation',
      () async {
    final storage = WatchlistStorage();
    await storage.upsert(
      AnimeProgress(
        subjectId: 900101,
        name: '关于我转生变成史莱姆这档事 第四季',
        coverUrl: '',
        currentEpisode: 12,
        totalEpisodes: 24,
        status: WatchStatus.watching,
        statusSelected: true,
        updateWeekday: 5,
        privateRating: 8,
        privateReview: '',
        reminderEnabled: true,
        reminderHour: 20,
        reminderMinute: 0,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      syncToCloud: false,
    );
    await storage.upsert(
      AnimeProgress(
        subjectId: 900102,
        name: '租借女友',
        coverUrl: '',
        currentEpisode: 12,
        totalEpisodes: 12,
        status: WatchStatus.finished,
        statusSelected: true,
        updateWeekday: 6,
        privateRating: 8,
        privateReview: '',
        reminderEnabled: false,
        reminderHour: 20,
        reminderMinute: 0,
        createdAtMs: DateTime.now().millisecondsSinceEpoch - 1000,
      ),
      syncToCloud: false,
    );

    final configStorage = LlmConfigStorage();
    await configStorage.saveConfig(
      const LlmConfig(
        llmName: 'fake-model',
        llmUrl: 'https://example.com/v1',
        llmKey: 'test-key',
        isEncrypted: false,
      ),
    );

    final fakeApi = _ScenarioBangumiApiService();
    final fakeLlm = _ScenarioLlmApiService();
    final service = AgentService(
      bangumiApiService: fakeApi,
      watchlistStorage: storage,
      configStorage: configStorage,
      llmApiService: fakeLlm,
    );

    final reply = await service.chat(
      userInput: '根据我的偏好推荐一些番吧',
      history: const <AgentMessage>[],
    );

    expect(fakeLlm.callCount, 3);
    expect(fakeLlm.sawPreferenceFlowPrompt, isTrue);
    expect(reply.text, contains('根据你的偏好标签'));
    expect(reply.text, contains('《葬送的芙莉莲》'));
    expect(reply.text, contains('《败犬女主太多了！》'));
    expect(reply.items.map((item) => item.id), contains(400602));
    expect(reply.items.map((item) => item.id), contains(464376));
    expect(
        fakeApi.tagSearchCalls,
        containsAll(<List<String>>[
          <String>['异世界', '奇幻'],
          <String>['恋爱', '校园'],
        ]));
  });
}

class _ScenarioBangumiApiService extends BangumiApiService {
  final List<List<String>> tagSearchCalls = <List<String>>[];

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
    if (tags.isNotEmpty) {
      tagSearchCalls.add(List<String>.from(tags));
    }
    if (_sameTags(tags, const <String>['异世界', '奇幻'])) {
      return AnimeSearchPage(
        total: 3,
        limit: limit,
        offset: offset,
        data: <AnimeCalendarItem>[
          _item(302523, '关于我转生变成史莱姆这档事 第二季 第2部分', 6.1, 545),
          _item(421174, '关于我转生变成史莱姆这档事 柯里乌斯之梦', 5.9, 136),
          _item(400602, '葬送的芙莉莲', 8.5, 11595),
        ],
      );
    }
    if (_sameTags(tags, const <String>['恋爱', '校园'])) {
      return AnimeSearchPage(
        total: 2,
        limit: limit,
        offset: offset,
        data: <AnimeCalendarItem>[
          _item(451644, '租借女友 第三季', 7.2, 120),
          _item(464376, '败犬女主太多了！', 8.0, 6969),
        ],
      );
    }
    if (_sameTags(tags, const <String>['悬疑'])) {
      return AnimeSearchPage(
        total: 1,
        limit: limit,
        offset: offset,
        data: <AnimeCalendarItem>[
          _item(214272, '欢迎来到实力至上主义的教室', 6.2, 723),
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
    if (id == 900101) {
      return _detail(id, '关于我转生变成史莱姆这档事 第四季',
          tags: const <String>['异世界', '奇幻']);
    }
    if (id == 900102) {
      return _detail(id, '租借女友', tags: const <String>['恋爱', '校园']);
    }
    throw Exception('not mocked');
  }

  bool _sameTags(List<String> a, List<String> b) {
    return a.length == b.length && a.toSet().containsAll(b);
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

  AnimeCalendarItem _item(int id, String name, double score, int doingCount) {
    return AnimeCalendarItem(
      id: id,
      name: name,
      coverUrl: '',
      airWeekday: 0,
      airDate: '2024-01-01',
      ratingScore: score,
      doingCount: doingCount,
      summary: '$name 的简介',
    );
  }
}

class _ScenarioLlmApiService extends LlmApiService {
  int callCount = 0;
  bool sawPreferenceFlowPrompt = false;

  @override
  Future<LlmChatResponse> chatCompletions({
    required LlmConfig config,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async {
    callCount += 1;
    if (callCount == 1) {
      return const LlmChatResponse(
        content: '',
        toolCalls: <LlmToolCall>[
          LlmToolCall(
            id: 'tool-call-1',
            name: 'GetUserPreferenceSeeds',
            arguments: <String, dynamic>{},
          ),
        ],
        rawResponse: <String, dynamic>{
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{
              'message': <String, dynamic>{
                'content': '',
                'tool_calls': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'tool-call-1',
                    'function': <String, dynamic>{
                      'name': 'GetUserPreferenceSeeds',
                      'arguments': '{}',
                    },
                  },
                ],
              },
            },
          ],
        },
      );
    }
    if (callCount == 2) {
      final systemText = messages
          .where((message) => message['role'] == 'system')
          .map((message) => message['content']?.toString() ?? '')
          .join('\n');
      sawPreferenceFlowPrompt =
          systemText.contains('先调用 GetUserPreferenceSeeds') &&
              systemText.contains('再由你自己设计 2~3 组 1~3 个标签去调用 AnimeSearchTool') &&
              systemText.contains(
                'excludeWatched=true、excludeSameSeries=true、recommendationMode=true',
              );

      final toolMessage =
          messages.lastWhere((message) => message['role'] == 'tool');
      final toolPayload = jsonDecode(toolMessage['content']!.toString())
          as Map<String, dynamic>;
      final payload = (toolPayload['payload'] as Map<String, dynamic>? ??
          const <String, dynamic>{});
      final allTags = (payload['all_preference_tags'] as List<dynamic>? ??
              const <dynamic>[])
          .map((item) => item.toString())
          .toList();
      expect(allTags, containsAll(<String>['异世界', '奇幻', '恋爱', '校园']));

      return const LlmChatResponse(
        content: '',
        toolCalls: <LlmToolCall>[
          LlmToolCall(
            id: 'tool-call-2',
            name: 'AnimeSearchTool',
            arguments: <String, dynamic>{
              'tags': <String>['异世界', '奇幻'],
              'limit': 6,
              'sort': 'heat',
              'excludeWatched': true,
              'excludeSameSeries': true,
              'recommendationMode': true,
            },
          ),
          LlmToolCall(
            id: 'tool-call-3',
            name: 'AnimeSearchTool',
            arguments: <String, dynamic>{
              'tags': <String>['恋爱', '校园'],
              'limit': 6,
              'sort': 'heat',
              'excludeWatched': true,
              'excludeSameSeries': true,
              'recommendationMode': true,
            },
          ),
          LlmToolCall(
            id: 'tool-call-4',
            name: 'AnimeSearchTool',
            arguments: <String, dynamic>{
              'tags': <String>['悬疑'],
              'limit': 5,
              'sort': 'score',
              'excludeWatched': true,
              'excludeSameSeries': true,
              'recommendationMode': true,
            },
          ),
        ],
        rawResponse: <String, dynamic>{
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{
              'message': <String, dynamic>{
                'content': '',
                'tool_calls': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'tool-call-2',
                    'function': <String, dynamic>{
                      'name': 'AnimeSearchTool',
                      'arguments':
                          '{"tags":["异世界","奇幻"],"limit":6,"sort":"heat","excludeWatched":true,"excludeSameSeries":true,"recommendationMode":true}',
                    },
                  },
                  <String, dynamic>{
                    'id': 'tool-call-3',
                    'function': <String, dynamic>{
                      'name': 'AnimeSearchTool',
                      'arguments':
                          '{"tags":["恋爱","校园"],"limit":6,"sort":"heat","excludeWatched":true,"excludeSameSeries":true,"recommendationMode":true}',
                    },
                  },
                  <String, dynamic>{
                    'id': 'tool-call-4',
                    'function': <String, dynamic>{
                      'name': 'AnimeSearchTool',
                      'arguments':
                          '{"tags":["悬疑"],"limit":5,"sort":"score","excludeWatched":true,"excludeSameSeries":true,"recommendationMode":true}',
                    },
                  },
                ],
              },
            },
          ],
        },
      );
    }

    final toolMessages =
        messages.where((message) => message['role'] == 'tool').toList();
    expect(toolMessages.length, greaterThanOrEqualTo(4));

    return const LlmChatResponse(
      content: '根据你的偏好标签，星奈这次优先挑了几部方向不同的新系列：\n\n'
          '1. 《葬送的芙莉莲》：异世界和奇幻氛围很强，但情感表达也很细腻。\n'
          '2. 《败犬女主太多了！》：恋爱校园方向会更贴近你另一部分口味，而且和已追系列不重复。\n'
          '3. 《欢迎来到实力至上主义的教室》：作为探索性补充，也适合换换口味。\n\n'
          '[[CARD_IDS: 400602,464376,214272]]',
      toolCalls: <LlmToolCall>[],
      rawResponse: <String, dynamic>{
        'choices': <Map<String, dynamic>>[
          <String, dynamic>{
            'message': <String, dynamic>{
              'content': '根据你的偏好标签，星奈这次优先挑了几部方向不同的新系列：\n\n'
                  '1. 《葬送的芙莉莲》：异世界和奇幻氛围很强，但情感表达也很细腻。\n'
                  '2. 《败犬女主太多了！》：恋爱校园方向会更贴近你另一部分口味，而且和已追系列不重复。\n'
                  '3. 《欢迎来到实力至上主义的教室》：作为探索性补充，也适合换换口味。\n\n'
                  '[[CARD_IDS: 400602,464376,214272]]',
            },
          },
        ],
      },
    );
  }
}
