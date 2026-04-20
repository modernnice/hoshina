import 'dart:convert';
import 'dart:io';

import 'package:drama_tracker/models/agent_message.dart';
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
    tempDir =
        await Directory.systemTemp.createTemp('real_api_agent_replay_test_');
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

  test('live agent replay with real Bangumi API and real LLM config', () async {
    final env = Platform.environment;
    final llmName = env['LIVE_LLM_MODEL'] ?? env['LLM_MODEL'] ?? '';
    final llmUrl = env['LIVE_LLM_URL'] ?? env['LLM_URL'] ?? '';
    final llmKey = env['LIVE_LLM_KEY'] ?? env['LLM_KEY'] ?? '';

    if (llmName.trim().isEmpty || llmUrl.trim().isEmpty) {
      fail(
        'Missing live LLM config. Set LIVE_LLM_MODEL/LIVE_LLM_URL(/LIVE_LLM_KEY) '
        'or LLM_MODEL/LLM_URL(/LLM_KEY) before running this test.',
      );
    }

    final storage = WatchlistStorage();
    final configStorage = LlmConfigStorage();
    final now = DateTime.now().millisecondsSinceEpoch;

    await configStorage.saveConfig(
      LlmConfig(
        llmName: llmName,
        llmUrl: llmUrl,
        llmKey: llmKey,
        isEncrypted: false,
        enableAgentDebugTrace: true,
        maxToolRounds: 6,
      ),
    );

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

    final service = AgentService(
      bangumiApiService: BangumiApiService(),
      watchlistStorage: storage,
      configStorage: configStorage,
      llmApiService: LlmApiService(),
    );

    final reply = await service.chat(
      userInput: '根据我的偏好推荐一些番吧',
      history: const <AgentMessage>[],
    );

    final selectedTagQueries = _extractSearchTagQueries(reply.debugTrace);

    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert({
      'selectedTagQueries': selectedTagQueries,
      'replyText': reply.text,
      'cardItems': [
        for (final item in reply.items)
          {
            'id': item.id,
            'name': item.name,
            'score': item.ratingScore,
            'doingCount': item.doingCount,
            'airDate': item.airDate,
          },
      ],
      'debugTrace': reply.debugTrace,
    }));

    expect(reply.text.trim(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

List<Map<String, dynamic>> _extractSearchTagQueries(String debugTrace) {
  final queries = <Map<String, dynamic>>[];
  final lines = const LineSplitter().convert(debugTrace);
  String? currentTool;
  for (final line in lines) {
    if (line.startsWith('调用工具：')) {
      currentTool = line.replaceFirst('调用工具：', '').trim();
      continue;
    }
    if (line.startsWith('参数：') && currentTool == '番剧搜索') {
      final rawJson = line.replaceFirst('参数：', '').trim();
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map<String, dynamic>) {
          queries.add(decoded);
        }
      } catch (_) {
        // Ignore malformed debug lines in this temporary live snapshot test.
      }
    }
  }
  return queries;
}
