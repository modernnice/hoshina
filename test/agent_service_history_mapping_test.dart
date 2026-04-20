import 'dart:io';

import 'package:drama_tracker/models/agent_message.dart';
import 'package:drama_tracker/models/llm_config.dart';
import 'package:drama_tracker/services/agent/agent_service.dart';
import 'package:drama_tracker/services/llm_api_service.dart';
import 'package:drama_tracker/services/llm_config_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late Box<Map> configBox;
  late Box<Map> watchlistBox;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('agent_history_test_');
    Hive.init(tempDir.path);
    configBox = await Hive.openBox<Map>('llm_config_box');
    watchlistBox = await Hive.openBox<Map>('watchlist');
  });

  tearDown(() async {
    await configBox.clear();
    await watchlistBox.clear();
  });

  tearDownAll(() async {
    await configBox.close();
    await watchlistBox.close();
    await tempDir.delete(recursive: true);
  });

  test('assistant raw history is not replayed as few-shot content', () async {
    final configStorage = LlmConfigStorage();
    await configStorage.saveConfig(
      const LlmConfig(
        llmName: 'fake-model',
        llmUrl: 'https://example.com/v1',
        llmKey: 'test-key',
        isEncrypted: false,
      ),
    );

    final fakeLlm = _CaptureHistoryLlmApiService();
    final service = AgentService(
      configStorage: configStorage,
      llmApiService: fakeLlm,
    );

    await service.chat(
      userInput: '青山吉能有哪些配音作品',
      history: const <AgentMessage>[
        AgentMessage(
          role: AgentMessageRole.user,
          content: '远野光有哪些配音作品',
        ),
        AgentMessage(
          role: AgentMessageRole.assistant,
          content: '**远野光（遠野ひかる）**是日本女性声优，响所属，东京都出身。'
              '以下是星奈查到的她配音过的部分角色：'
              '| 角色 | 作品 | 角色定位 |',
        ),
      ],
    );

    final messages = fakeLlm.lastMessages;
    expect(messages, isNotEmpty);

    final contents = messages
        .map((message) => message['content']?.toString() ?? '')
        .join('\n');

    expect(contents, contains('远野光有哪些配音作品'));
    expect(contents, isNot(contains('**远野光（遠野ひかる）**是日本女性声优')));
    expect(contents, isNot(contains('| 角色 | 作品 | 角色定位 |')));
    expect(contents, contains('系统上下文：上一轮 assistant 已完成回复。'));
    expect(contents, contains('不要模仿上一轮 assistant 的措辞、排版或结论'));
  });
}

class _CaptureHistoryLlmApiService extends LlmApiService {
  List<Map<String, dynamic>> lastMessages = const <Map<String, dynamic>>[];

  @override
  Future<LlmChatResponse> chatCompletions({
    required LlmConfig config,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async {
    lastMessages = List<Map<String, dynamic>>.from(messages);
    return const LlmChatResponse(
      content: '测试回复',
      toolCalls: <LlmToolCall>[],
      rawResponse: <String, dynamic>{
        'choices': <Map<String, dynamic>>[
          <String, dynamic>{
            'message': <String, dynamic>{
              'content': '测试回复',
            },
          },
        ],
      },
    );
  }
}
