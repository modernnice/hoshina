import 'dart:convert';

import 'package:drama_tracker/models/agent_message.dart';
import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/models/llm_config.dart';
import 'package:drama_tracker/services/agent/agent_dispatcher.dart';
import 'package:drama_tracker/services/agent/agent_models.dart';
import 'package:drama_tracker/services/agent/anime_control_tool.dart';
import 'package:drama_tracker/services/agent/anime_character_tool.dart';
import 'package:drama_tracker/services/agent/anime_detail_tool.dart';
import 'package:drama_tracker/services/agent/anime_search_tool.dart';
import 'package:drama_tracker/services/agent/character_search_tool.dart';
import 'package:drama_tracker/services/agent/current_time_tool.dart';
import 'package:drama_tracker/services/agent/get_user_preference_seeds_tool.dart';
import 'package:drama_tracker/services/agent/person_character_tool.dart';
import 'package:drama_tracker/services/agent/person_search_tool.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/services/llm_api_service.dart';
import 'package:drama_tracker/services/llm_config_storage.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';

class AgentService {
  static const int _maxSameToolExecutionCount = 6;

  AgentService({
    BangumiApiService? bangumiApiService,
    WatchlistStorage? watchlistStorage,
    LlmConfigStorage? configStorage,
    LlmApiService? llmApiService,
  })  : _api = bangumiApiService ?? BangumiApiService(),
        _storage = watchlistStorage ?? WatchlistStorage(),
        _configStorage = configStorage ?? LlmConfigStorage(),
        _llmApi = llmApiService ?? LlmApiService() {
    _dispatcher = AgentDispatcher(
      tools: [
        CurrentTimeTool(),
        AnimeSearchTool(_api, _storage),
        AnimeDetailTool(_api),
        PersonSearchTool(_api),
        PersonCharacterTool(_api),
        CharacterSearchTool(_api),
        AnimeCharacterTool(_api),
        GetUserPreferenceSeedsTool(_api, _storage),
        AnimeControlTool(_storage, _api),
      ],
    );
  }

  final BangumiApiService _api;
  final WatchlistStorage _storage;
  final LlmConfigStorage _configStorage;
  final LlmApiService _llmApi;
  late final AgentDispatcher _dispatcher;

  LlmConfig? get currentConfig => _configStorage.getConfig();

  Future<AgentReply> chat({
    required String userInput,
    required List<AgentMessage> history,
    void Function(List<String> chain)? onToolChainUpdate,
  }) async {
    final config = _configStorage.getConfig();
    if (config == null || !config.isValid) {
      return const AgentReply(
        text: '在使用星奈之前，记得先去设置页填写模型名称和 API URL 哦，这样星奈才能正常帮你工作～',
      );
    }
    final enableDebugTrace = config.enableAgentDebugTrace;
    final maxToolRounds = config.normalizedMaxToolRounds;
    final selectedClarification =
        _resolveClarificationSelection(history, userInput);
    final traceLines = <String>[];
    if (enableDebugTrace) {
      traceLines.addAll([
        '模式：开发态调试轨迹（不含原始内部 chain-of-thought）',
        '任务：${userInput.trim()}',
        '模型：${config.llmName.trim()}',
        '工具轮次上限：$maxToolRounds',
      ]);
    }
    if (selectedClarification != null) {
      traceLines.add(
        '上下文：用户确认了上一轮候选《${selectedClarification.item.name}》'
        '（subjectId=${selectedClarification.option.subjectId ?? selectedClarification.item.id}）。',
      );
    }
    var rounds = 0;
    AgentReply replyWithTrace({
      required String text,
      List<AnimeCalendarItem> items = const [],
      List<AgentMessageOption> options = const [],
    }) {
      final toolTrace =
          enableDebugTrace ? _buildExecutionTrace(traceLines) : '';
      return AgentReply(
        text: text,
        items: items,
        options: options,
        debugTrace: toolTrace,
      );
    }

    Future<AgentReply> replyWithLlmClarification({
      required List<Map<String, dynamic>> transcriptMessages,
      required String traceReason,
      required String systemPrompt,
    }) async {
      traceLines.add(traceReason);
      final clarificationTranscript = <Map<String, dynamic>>[
        ...transcriptMessages,
        {'role': 'system', 'content': systemPrompt},
      ];
      final clarificationStep = await _llmApi.chatCompletions(
        config: config,
        messages: clarificationTranscript,
        tools: const [],
      );
      if (enableDebugTrace) {
        traceLines.addAll(
          _buildLlmStepTrace(
            step: clarificationStep,
            stepIndex: rounds + 1,
            transcript: clarificationTranscript,
            tools: const [],
          ),
        );
      }
      final clarificationText = clarificationStep.content.trim();
      if (clarificationText.isEmpty) {
        traceLines.add('收束：歧义追问阶段模型未返回正文，使用本地回退回复。');
        return replyWithTrace(text: '星奈这边还需要你再补充一点目标信息，这样才能继续处理。');
      }
      traceLines.add('收束：由模型生成歧义追问。');
      return replyWithTrace(text: clarificationText);
    }

    final mappedHistory = _mapHistory(history);
    final hasCurrentUserInHistory = mappedHistory.isNotEmpty &&
        mappedHistory.last['role'] == 'user' &&
        (mappedHistory.last['content']?.toString().trim() ?? '') ==
            userInput.trim();
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': '你是用户专属的二次元追番助手“星奈（Hoshina）”。'
            '默认用中文回答，语气自然、简洁、友好。'
            '严禁使用“我”作为第一人称，统一使用“星奈”。'
            '用户提出的任务可能五花八门，你的最终目标是理解并解决用户真正的问题，而不是为了调用工具而调用工具，也不是只搜到一个结果就停止。'
            '必须使用工具获取事实，禁止凭记忆编造番剧信息。'
            '可以连续多次调用工具，直到拿到足够信息再回答。'
            '若问题涉及“现在/最近/本月/本季/今年/最新/已播出/计划中”等时间判断，先获取真实时间再推断。'
            '详情、角色或控制操作如果目标作品不明确，可以先搜索再继续；如果用户是在确认上一轮候选，这表示继续上一轮任务，不是新请求。'
            '如果用户是在比较两个作品或两个系列哪个更好看、哪个更值得看、有什么区别，且其中一方命中多个季、篇、剧场版或衍生作，优先选择该系列最常见的主系列代表作继续比较，不要因为季数或剧场版分支先打断用户确认。'
            '当用户要求“基于偏好/追番记录推荐”时，优先先调用 GetUserPreferenceSeeds 获取用户高权重种子和全局偏好标签，再由你自己设计 2~3 组 1~3 个标签去调用 AnimeSearchTool。'
            '推荐场景下调用 AnimeSearchTool 时，应优先设置 excludeWatched=true、excludeSameSeries=true、recommendationMode=true。'
            '如果用户进一步补充了题材、原创/漫画改、年份范围、评分门槛、热度门槛或排名范围等条件，也应继续通过 AnimeSearchTool 的 tags、metaTags、airDate、rating、ratingCount、rank 等参数表达。'
            'AnimeSearchTool 中多个标签表示交集搜索，适合用来做高置信度组合推荐；单标签可用于探索补充。'
            '推荐场景里的 sort 不要明显偏向单一维度；应结合组合目标在 heat 和 rank 之间做平衡：有的查询更适合用 heat 找热门当下作品，有的查询更适合用 rank 找口碑稳定作品。'
            '优先混合“高置信度双标签/三标签组合”和“探索性单标签”来增加结果多样性，不要只围绕一个标签方向反复搜索。'
            '即使 AnimeSearchTool 已开启排除已追和同系列作品，你在最终组织答案时仍要避免连续推荐风格过于相似的作品，尽量让题材、年代和气质更分散。'
            'PersonSearchTool 只用于检索现实中的人物，包括导演、编剧、声优等从业者。'
            'PersonCharacterTool 只用于在现实人物已经明确时，继续查询这个人物关联到哪些角色，最常用于根据声优 id 查询配音角色。'
            'CharacterSearchTool 只用于按角色名搜索角色，例如“介绍一下无惨这个角色”“搜索阿尼亚”。'
            'AnimeCharacterTool 只用于在作品已经明确时查询该作品的角色与声优列表，例如“这部番有哪些角色”“主角是谁”“这部番的出演声优有哪些”。'
            '如果用户要查询某部番的出演声优，必须在作品明确后调用 AnimeCharacterTool 获取角色与声优信息。'
            '如果用户要查询某部番的制作人员，例如导演、编剧、制作公司等，必须调用 AnimeDetailTool，从详情接口返回的制作班底/infobox 等字段中提取。'
            '如果用户是在问单独某一个真实人物，例如某位导演、编剧或声优是谁，必须调用 PersonSearchTool 获取人物信息。'
            '如果用户是在问某位真实人物配过哪些角色、关联了哪些角色，必须先明确该人物，再调用 PersonCharacterTool。'
            '如果用户是在问现实人物，例如“花江夏树是谁”“这部番的导演是谁”“找一下新海诚”，优先调用 PersonSearchTool。'
            '当你回答现实人物介绍时，只能陈述 PersonSearchTool 实际返回过的字段；PersonSearchTool 没有返回的生日、事务所、奖项、代表作、经历等信息，一律不得自行补写。'
            '当用户询问声优“配过哪些作品/角色”时，不能只靠 PersonSearchTool 的摘要作答，必须继续调用 PersonCharacterTool；如果还缺作品名或角色名，就明确说明当前工具结果不足，不能猜。'
            '如果 PersonCharacterTool 没有返回角色所属作品，严禁自己补全作品名；只能回答已确认的角色名，并明确说明所属作品信息暂未从工具结果中取得。'
            '如果 PersonSearchTool 返回了多个候选人物，除非存在高置信度精确匹配且职业也吻合，否则应先向用户确认，不要擅自选择并展开介绍。'
            '必须严格区分三种 id：作品（番剧）id 是 subjectId，角色 id 是 characterId，现实人物 id 是 personId，它们是三个不同的 id，绝不能混淆。'
            'PersonSearchTool 返回的是 personId；CharacterSearchTool 和 PersonCharacterTool 返回的角色 id 是 characterId；AnimeSearchTool、AnimeDetailTool 和 AnimeCharacterTool 使用的是 subjectId。'
            '角色搜索结果里的 id 是 characterId，不是 subjectId；人物搜索结果里的 id 是 personId，不是 characterId，也不是 subjectId。'
            '不能把 personId 传给 AnimeDetailTool，也不能把 characterId 传给 AnimeDetailTool 或 PersonCharacterTool。'
            '如果用户是在询问某个角色本身，优先调用 CharacterSearchTool；只有在作品目标已经明确时，才调用 AnimeCharacterTool。'
            '涉及角色信息时，必须通过 CharacterSearchTool、AnimeCharacterTool 或 PersonCharacterTool 获取；涉及真实人物信息时，必须通过 PersonSearchTool、AnimeDetailTool 或 AnimeCharacterTool 获取；不得凭记忆补全、猜测或编造。'
            'AnimeControlTool 只用于本地追番列表操作，包括添加、删除、状态修改、进度更新和提醒开关。'
            '当前详情接口会附带番剧制作班底字段，但这些字段可能零散且不稳定；涉及现实人物信息时，应优先以 PersonSearchTool 的检索结果为准。'
            '如果仍然没有明确检索到目标人物，不能伪造答案，必须向用户说明；'
            '如果你希望在最终回复中展示番剧卡片，请在正文最后单独添加一行 [[CARD_IDS: subjectId1,subjectId2,...]]。'
            '如果不需要展示卡片，就不要添加这行。'
            '只能填写本轮工具结果里已经出现过的 subjectId，不要解释这个标记本身。'
            '不要输出工具结构、调试文本或机械化说明。除非用户明确询问当前时间，否则不要主动展示系统时间。'
            '回答时简洁清晰，优先引用工具返回的关键信息；如果信息不足，就先继续调用工具，不要猜。'
      },
      if (selectedClarification != null)
        {
          'role': 'system',
          'content': '用户刚刚已经在上一轮候选中明确选择了《${selectedClarification.option.value}》'
              '（subjectId=${selectedClarification.option.subjectId ?? selectedClarification.item.id}）。'
              '这是一条对上一轮歧义候选的确认，不是新的独立检索请求。'
              '${_buildClarificationContinuationInstruction(selectedClarification)}',
        },
      ...mappedHistory,
      if (!hasCurrentUserInHistory) {'role': 'user', 'content': userInput},
    ];
    final tools = _dispatcher.buildToolSchemas();

    final aggregatedItems = <AnimeCalendarItem>[];
    final detailItems = <AnimeCalendarItem>[];
    final summaries = <String>[];
    Map<String, dynamic>? characterPayload;
    final lockedSubjectCandidate = selectedClarification?.item;
    List<AnimeCalendarItem> latestSearchItems = lockedSubjectCandidate == null
        ? const []
        : <AnimeCalendarItem>[lockedSubjectCandidate];
    Map<String, dynamic>? latestSearchPayload;
    final transcript = <Map<String, dynamic>>[...messages];
    final toolChain = <String>[];
    final toolExecutionCounts = <String, int>{};
    final currentTime = DateTime.now();

    LlmChatResponse step = await _llmApi.chatCompletions(
      config: config,
      messages: transcript,
      tools: tools,
    );
    if (enableDebugTrace) {
      traceLines.addAll(
        _buildLlmStepTrace(
          step: step,
          stepIndex: 1,
          transcript: transcript,
          tools: tools,
        ),
      );
    }

    var shouldStopToolLoop = false;
    while (step.toolCalls.isNotEmpty && rounds < maxToolRounds) {
      rounds += 1;
      final reactThought = _buildReactThoughtFromStep(
        step: step,
        plannedToolCalls: step.toolCalls,
      );
      traceLines.add('思路摘要：$reactThought');
      for (final call in step.toolCalls) {
        toolChain.add(call.name);
        onToolChainUpdate?.call(List<String>.from(toolChain));
        traceLines.add('调用工具：${_toolDisplayName(call.name)}');
        var effectiveArguments = Map<String, dynamic>.from(call.arguments);
        if (_shouldLockClarifiedSubject(call.name, selectedClarification) &&
            lockedSubjectCandidate != null) {
          effectiveArguments['subjectId'] = lockedSubjectCandidate.id;
          effectiveArguments['animeId'] = lockedSubjectCandidate.id;
          effectiveArguments['animeName'] = lockedSubjectCandidate.name;
          final controlIntent = selectedClarification?.option.controlIntent;
          if (call.name == 'AnimeControlTool' &&
              controlIntent != null &&
              controlIntent.isNotEmpty) {
            effectiveArguments['intent'] = controlIntent;
          }
        } else if (_shouldResolveSubjectFromSearchResults(
                call.name, effectiveArguments) &&
            latestSearchItems.isNotEmpty) {
          final expandedCandidates = await _expandSearchCandidatesIfNeeded(
            candidates: latestSearchItems,
            searchPayload: latestSearchPayload,
          );
          if (expandedCandidates.isNotEmpty) {
            latestSearchItems = expandedCandidates;
          }
          final resolution = _resolveSubjectFromSearchResults(
            userInput: userInput,
            candidates: latestSearchItems,
            searchPayload: latestSearchPayload,
          );
          if (resolution.exactItem != null) {
            effectiveArguments['subjectId'] = resolution.exactItem!.id;
            traceLines.add(
                '解析目标：命中《${resolution.exactItem!.name}》（subjectId=${resolution.exactItem!.id}）。');
          } else if (resolution.needsClarification) {
            final candidateSummary = resolution.candidates.map((item) {
              final date = item.airDate.trim();
              return '《${item.name}》${date.isNotEmpty ? '（$date）' : ''}';
            }).join('、');
            return await replyWithLlmClarification(
              transcriptMessages: transcript,
              traceReason: '结果：候选存在歧义，改由模型向用户追问更多信息。',
              systemPrompt: '系统提示：你要查询的目标作品存在歧义，当前无法安全继续。'
                  '候选包括：$candidateSummary。'
                  '请你基于这些候选，用自然中文向用户明确追问还需要哪一部。'
                  '不要输出按钮、编号选项、工具结构或调试文本，也不要继续调用任何工具。'
                  '如果合适，可以简短点名几个最关键候选，但核心目标是让用户补充信息。',
            );
          }
        }
        final executionSignature =
            _buildToolExecutionSignature(call.name, effectiveArguments);
        final executionCount = toolExecutionCounts[executionSignature] ?? 0;
        final nextExecutionCount = executionCount + 1;
        toolExecutionCounts[executionSignature] = nextExecutionCount;
        if (executionCount > 0) {
          traceLines.add(
            '告警：${_toolDisplayName(call.name)} 相同参数已重复调用 $nextExecutionCount 次，'
            '历史中已存在对应结果，优先提示模型复用已有结果。',
          );
          transcript.add({
            'role': 'system',
            'content': '系统提示：你刚刚再次请求了相同的工具与参数。'
                '当前对话历史里已经包含这组调用的结果，请优先复用已有结果继续推理，'
                '除非你准备改用不同参数或调用不同工具。'
                '重复工具：${call.name}；重复次数：$nextExecutionCount。',
          });
        }
        if (nextExecutionCount >= _maxSameToolExecutionCount) {
          traceLines.add(
            '终止：${_toolDisplayName(call.name)} 相同参数已连续调用 $nextExecutionCount 次，'
            '达到保护阈值 $_maxSameToolExecutionCount，停止继续执行以避免无效循环。',
          );
          shouldStopToolLoop = true;
          step = const LlmChatResponse(content: '', toolCalls: []);
          break;
        }
        if (enableDebugTrace) {
          traceLines.add('参数：${_stringifyDebugJson(effectiveArguments)}');
        }
        final result = _decorateResultWithTemporalContext(
          toolName: call.name,
          result: await _dispatcher.execute(call.name, effectiveArguments),
          currentTime: currentTime,
        );
        traceLines.add(_summarizeToolOutcome(call.name, result));
        if (enableDebugTrace) {
          traceLines.add('工具返回：${_summarizeToolResultForDebug(result)}');
        }
        final controlClarification = _buildControlClarificationReply(result);
        if (controlClarification != null) {
          final candidateSummary = controlClarification.items.map((item) {
            final date = item.airDate.trim();
            return '《${item.name}》${date.isNotEmpty ? '（$date）' : ''}';
          }).join('、');
          return await replyWithLlmClarification(
            transcriptMessages: transcript,
            traceReason: '结果：操作对象存在歧义，改由模型向用户追问更多信息。',
            systemPrompt: '系统提示：当前追番列表操作存在目标歧义，不能继续执行。'
                '候选包括：$candidateSummary。'
                '请你用自然中文向用户追问想操作的具体作品。'
                '不要输出按钮、编号选项、工具结构或调试文本，也不要继续调用任何工具。'
                '需要强调这是写操作，目标不明确时不能乱改。',
          );
        }
        if (call.name == 'AnimeSearchTool') {
          latestSearchItems = _dedupeItems(result.items);
          latestSearchPayload = result.payload;
        }
        if (call.name == 'AnimeDetailTool' && result.items.isNotEmpty) {
          detailItems.addAll(result.items);
        } else if (call.name == 'AnimeCharacterTool' ||
            call.name == 'CharacterSearchTool' ||
            call.name == 'PersonSearchTool') {
          characterPayload = result.payload;
        } else if (detailItems.isEmpty) {
          aggregatedItems.addAll(result.items);
        }
        if (!_isNoisyToolSummary(call.name, result.message)) {
          summaries.add(result.message);
        }
        transcript.add({
          'role': 'assistant',
          'tool_calls': [
            {
              'id': call.id,
              'type': 'function',
              'function': {
                'name': call.name,
                'arguments': jsonEncode(effectiveArguments),
              },
            }
          ],
        });
        transcript.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'content': jsonEncode(result.toJson()),
        });
      }
      if (shouldStopToolLoop) {
        break;
      }
      step = await _llmApi.chatCompletions(
        config: config,
        messages: transcript,
        tools: tools,
      );
      if (enableDebugTrace) {
        traceLines.addAll(
          _buildLlmStepTrace(
            step: step,
            stepIndex: rounds + 1,
            transcript: transcript,
            tools: tools,
          ),
        );
      }
    }
    if (enableDebugTrace &&
        step.toolCalls.isNotEmpty &&
        rounds >= maxToolRounds) {
      traceLines.add('终止：已达到工具轮次上限，停止继续调用工具。');
    }

    final outputItems = _dedupeItems(<AnimeCalendarItem>[
      ...aggregatedItems,
      ...detailItems,
    ]);
    final usedSearchTool = toolChain.contains('AnimeSearchTool');
    final usedDetailTool = toolChain.contains('AnimeDetailTool');
    final usedPreferenceRecommendTool =
        toolChain.contains('GetUserPreferenceSeeds');
    final usedControlTool = toolChain.contains('AnimeControlTool');
    final raw = step.content.trim();
    if (raw.isEmpty) {
      traceLines.add('收束：模型未返回正文，使用本地回退回复。');
      return replyWithTrace(
        text: _buildNaturalFallbackReply(
          items: const [],
          summaries: summaries,
          usedSearchTool: usedSearchTool,
          usedDetailTool: usedDetailTool,
          usedPreferenceRecommendTool: usedPreferenceRecommendTool,
          characterPayload: characterPayload,
          usedControlTool: usedControlTool,
        ),
      );
    }
    final cardDirective = _parseCardDirective(raw);
    final cleanedText = _stripCardDirectives(raw).trim();
    final selectedItems = _selectItemsFromCardDirective(
      items: outputItems,
      subjectIds: cardDirective,
    );
    if (cardDirective.isNotEmpty) {
      traceLines.add('卡片控制：模型指定展示 subjectId=${cardDirective.join(', ')}。');
    } else {
      traceLines.add('卡片控制：模型未指定卡片，返回空卡片集。');
    }
    if (cleanedText.isEmpty) {
      traceLines.add('收束：模型只返回了卡片标记，正文为空，使用本地回退回复。');
      return replyWithTrace(
        text: _buildNaturalFallbackReply(
          items: const [],
          summaries: summaries,
          usedSearchTool: usedSearchTool,
          usedDetailTool: usedDetailTool,
          usedPreferenceRecommendTool: usedPreferenceRecommendTool,
          characterPayload: characterPayload,
          usedControlTool: usedControlTool,
        ),
        items: selectedItems,
      );
    }
    traceLines.add('收束：生成最终回复。');
    return replyWithTrace(text: cleanedText, items: selectedItems);
  }

  List<Map<String, dynamic>> _mapHistory(List<AgentMessage> history) {
    final start = history.length > 24 ? history.length - 24 : 0;
    final recent = history.sublist(start);
    final mapped = <Map<String, dynamic>>[];
    for (final e in recent) {
      if (e.role == AgentMessageRole.user) {
        mapped.add({'role': 'user', 'content': e.content});
        continue;
      }

      if (e.role == AgentMessageRole.system) {
        mapped.add({'role': 'system', 'content': e.content});
        continue;
      }

      final assistantContext = _buildAssistantHistoryContext(e);
      if (assistantContext.isNotEmpty) {
        mapped.add({
          'role': 'system',
          'content': '系统上下文：上一轮 assistant 已完成回复。'
              '$assistantContext'
              '这段摘要只用于延续任务状态，不要模仿上一轮 assistant 的措辞、排版或结论。'
              '请优先根据用户最新问题和本轮工具结果重新组织回答。'
        });
      }

      if (e.items.isNotEmpty) {
        final itemsContext = e.items
            .asMap()
            .entries
            .map((entry) =>
                '第${entry.key + 1}部:《${entry.value.name}》(subjectId: ${entry.value.id})')
            .join('，');
        mapped.add({
          'role': 'system',
          'content': '系统上下文：上一轮 assistant 已经向用户展示过以下番剧卡片：'
              '$itemsContext。'
              '这段信息只用于帮助你避免重复推荐，并在需要时正确输出 [[CARD_IDS: ...]]。'
              '不要把这段系统上下文原样复述给用户，也不要输出“系统备注”字样。'
        });
      }
    }
    return mapped;
  }

  String _buildAssistantHistoryContext(AgentMessage message) {
    final parts = <String>[];
    final trimmedContent = message.content.trim();
    if (trimmedContent.isNotEmpty) {
      parts.add('上一轮任务类型：${_classifyAssistantHistory(trimmedContent)}。');
    }
    if (message.options.isNotEmpty) {
      final labels = message.options
          .map((option) => option.label.trim())
          .where((label) => label.isNotEmpty)
          .toList();
      if (labels.isNotEmpty) {
        parts.add('上一轮给出过 ${labels.length} 个候选项：${labels.join('、')}。');
      }
    }
    return parts.join();
  }

  String _classifyAssistantHistory(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return '已完成上一轮回复';
    }
    if (normalized.contains('配音') || normalized.contains('声优')) {
      return '声优或角色相关查询';
    }
    if (normalized.contains('推荐')) {
      return '番剧推荐';
    }
    if (normalized.contains('简介') || normalized.contains('介绍')) {
      return '作品详情介绍';
    }
    if (normalized.contains('角色')) {
      return '角色信息查询';
    }
    if (normalized.contains('提醒') ||
        normalized.contains('看到第') ||
        normalized.contains('想看') ||
        normalized.contains('在看') ||
        normalized.contains('看完')) {
      return '追番列表操作';
    }
    return '已完成上一轮回复';
  }

  List<AnimeCalendarItem> _dedupeItems(List<AnimeCalendarItem> items) {
    final seen = <int>{};
    final result = <AnimeCalendarItem>[];
    for (final item in items) {
      if (item.id <= 0 || seen.contains(item.id)) {
        continue;
      }
      seen.add(item.id);
      result.add(item);
    }
    return result;
  }

  String _buildExecutionTrace(List<String> lines) {
    if (lines.isEmpty) {
      return '';
    }
    return lines.join('\n');
  }

  List<String> _buildLlmStepTrace({
    required LlmChatResponse step,
    required int stepIndex,
    required List<Map<String, dynamic>> transcript,
    required List<Map<String, dynamic>> tools,
  }) {
    final outputToolCalls = step.toolCalls
        .map(
          (call) => {
            'id': call.id,
            'name': call.name,
            'arguments': call.arguments,
          },
        )
        .toList();
    return <String>[
      '----- LLM 第 $stepIndex 轮 BEGIN -----',
      '输入 messages（完整）:',
      _prettyJson(transcript),
      '输入 tools（完整）:',
      _prettyJson(tools),
      '输出 content（完整）:',
      step.content,
      '输出 tool_calls（完整）:',
      _prettyJson(outputToolCalls),
      '输出 raw_response_json（完整）:',
      _prettyJson(step.rawResponse),
      '----- LLM 第 $stepIndex 轮 END -----',
    ];
  }

  String _buildReactThoughtFromStep({
    required LlmChatResponse step,
    required List<LlmToolCall> plannedToolCalls,
  }) {
    final choices = step.rawResponse['choices'];
    if (choices is List &&
        choices.isNotEmpty &&
        choices.first is Map<String, dynamic>) {
      final message = (choices.first as Map<String, dynamic>)['message'];
      if (message is Map<String, dynamic>) {
        final reasoning = message['reasoning_content']?.toString().trim() ?? '';
        if (reasoning.isNotEmpty) {
          return _truncateDebugText(reasoning, maxLength: 800);
        }
      }
    }
    final toolNames = plannedToolCalls
        .map((call) => _toolDisplayName(call.name))
        .toSet()
        .join('、');
    if (toolNames.isEmpty) {
      return '准备基于当前信息直接生成回复。';
    }
    return '准备调用$toolNames，补充关键事实后再生成最终回复。';
  }

  String _summarizeToolResultForDebug(AgentToolResult result) {
    final payloadPreview = result.payload.isEmpty
        ? '无 payload'
        : _truncateDebugText(_stringifyDebugJson(result.payload),
            maxLength: 280);
    return 'success=${result.success}，message=${_truncateDebugText(result.message, maxLength: 120)}，'
        'items=${result.items.length}，payload=$payloadPreview';
  }

  String _stringifyDebugJson(Map<String, dynamic> value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  String _prettyJson(Object? value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value?.toString() ?? 'null';
    }
  }

  String _truncateDebugText(String text, {int maxLength = 160}) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}...';
  }

  String _toolDisplayName(String toolName) {
    switch (toolName) {
      case 'CurrentTimeTool':
        return '当前时间获取';
      case 'AnimeSearchTool':
        return '番剧搜索';
      case 'AnimeDetailTool':
        return '番剧详情';
      case 'PersonSearchTool':
        return '人物搜索';
      case 'PersonCharacterTool':
        return '人物关联角色查询';
      case 'CharacterSearchTool':
        return '角色搜索';
      case 'AnimeCharacterTool':
        return '番剧角色查询';
      case 'GetUserPreferenceSeeds':
        return '偏好种子提取';
      case 'AnimeControlTool':
        return '追番列表操作';
      default:
        return toolName;
    }
  }

  String _summarizeToolOutcome(String toolName, AgentToolResult result) {
    final prefix = '结果：';
    if (!result.success) {
      return '$prefix${_toolDisplayName(toolName)}失败，${result.message}';
    }
    switch (toolName) {
      case 'AnimeSearchTool':
        return '$prefix${_toolDisplayName(toolName)}返回 ${result.items.length} 个候选。';
      case 'AnimeDetailTool':
        return result.items.isNotEmpty
            ? '$prefix 已获取《${result.items.first.name}》的详情。'
            : '$prefix 已完成详情查询。';
      case 'AnimeCharacterTool':
        final count =
            int.tryParse((result.payload['count'] ?? 0).toString()) ?? 0;
        return '$prefix 已获取${count > 0 ? ' $count 位角色' : ''}角色信息。';
      case 'CharacterSearchTool':
        final count =
            int.tryParse((result.payload['count'] ?? 0).toString()) ?? 0;
        return '$prefix 已搜索到${count > 0 ? ' $count 位相关角色' : ''}。';
      case 'PersonSearchTool':
        final count =
            int.tryParse((result.payload['count'] ?? 0).toString()) ?? 0;
        return '$prefix 已搜索到${count > 0 ? ' $count 位相关人物' : ''}。';
      case 'GetUserPreferenceSeeds':
        final seedCount =
            (result.payload['seeds'] as List<dynamic>? ?? const <dynamic>[])
                .length;
        final tagCount =
            (result.payload['all_preference_tags'] as List<dynamic>? ??
                    const <dynamic>[])
                .length;
        return '$prefix 已提取 $seedCount 个偏好种子，并整理出 $tagCount 个偏好标签。';
      case 'AnimeControlTool':
        return '$prefix ${result.message}';
      default:
        return '$prefix ${result.message}';
    }
  }

  AgentToolResult _decorateResultWithTemporalContext({
    required String toolName,
    required AgentToolResult result,
    required DateTime currentTime,
  }) {
    if (result.items.isEmpty) {
      return result;
    }
    if (toolName != 'AnimeSearchTool' && toolName != 'AnimeDetailTool') {
      return result;
    }

    final temporalFacts = <Map<String, dynamic>>[];
    for (final item in result.items.take(10)) {
      final fact = _buildTemporalFact(item, currentTime);
      if (fact != null) {
        temporalFacts.add(fact);
      }
    }
    if (temporalFacts.isEmpty) {
      return result;
    }

    return AgentToolResult(
      success: result.success,
      message: result.message,
      items: result.items,
      payload: {
        ...result.payload,
        'currentDate': _formatDate(currentTime),
        'temporalFacts': temporalFacts,
      },
    );
  }

  Map<String, dynamic>? _buildTemporalFact(
      AnimeCalendarItem item, DateTime currentTime) {
    final airDate = _parseAirDate(item.airDate);
    if (airDate == null) {
      return null;
    }
    final today =
        DateTime(currentTime.year, currentTime.month, currentTime.day);
    final releaseDay = DateTime(airDate.year, airDate.month, airDate.day);
    final dayDiff = releaseDay.difference(today).inDays;
    final status = dayDiff > 0 ? 'upcoming' : 'released';
    return {
      'id': item.id,
      'name': item.name,
      'airDate': item.airDate,
      'status': status,
      'statusText': status == 'released' ? '已播出' : '计划播出',
      'daysDiff': dayDiff.abs(),
    };
  }

  DateTime? _parseAirDate(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(trimmed);
    if (match == null) {
      return null;
    }
    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day);
  }

  String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  bool _isNoisyToolSummary(String toolName, String message) {
    final text = message.trim();
    if (text.isEmpty) {
      return true;
    }
    if (toolName == 'CurrentTimeTool' || toolName == 'AnimeSearchTool') {
      return true;
    }
    if (RegExp(r'^找到\s*\d+\s*部番剧$').hasMatch(text)) {
      return true;
    }
    if (text.startsWith('当前时间：')) {
      return true;
    }
    return false;
  }

  String _buildNaturalFallbackReply({
    required List<AnimeCalendarItem> items,
    required List<String> summaries,
    required bool usedSearchTool,
    required bool usedDetailTool,
    required bool usedPreferenceRecommendTool,
    required bool usedControlTool,
    Map<String, dynamic>? characterPayload,
  }) {
    final cleanedSummaries = summaries
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((e) => !_isNoisyToolSummary('', e))
        .toList();

    if (items.isNotEmpty) {
      return '星奈帮你找到了 ${items.length} 部相关番剧，结果已经列在下方咯。';
    }

    if (cleanedSummaries.isNotEmpty) {
      return cleanedSummaries.join('\n');
    }
    return '非常抱歉，这次星奈还没找到合适结果，你可以换个描述再让星奈试试哦～';
  }

  List<AnimeCalendarItem> _selectItemsFromCardDirective({
    required List<AnimeCalendarItem> items,
    required List<int> subjectIds,
  }) {
    if (items.isEmpty || subjectIds.isEmpty) {
      return const [];
    }
    final byId = <int, AnimeCalendarItem>{};
    for (final item in items) {
      if (item.id > 0) {
        byId[item.id] = item;
      }
    }
    final selected = <AnimeCalendarItem>[];
    final seen = <int>{};
    for (final subjectId in subjectIds) {
      final item = byId[subjectId];
      if (item == null || seen.contains(subjectId)) {
        continue;
      }
      seen.add(subjectId);
      selected.add(item);
    }
    return selected;
  }

  List<int> _parseCardDirective(String text) {
    final matches = RegExp(r'\[\[CARD_IDS:\s*([0-9,\s]+)\]\]').allMatches(text);
    final ids = <int>[];
    final seen = <int>{};
    for (final match in matches) {
      final rawIds = match.group(1) ?? '';
      for (final part in rawIds.split(',')) {
        final value = int.tryParse(part.trim()) ?? 0;
        if (value <= 0 || seen.contains(value)) {
          continue;
        }
        seen.add(value);
        ids.add(value);
      }
    }
    if (ids.isNotEmpty) {
      return ids;
    }
    final leakedIds = RegExp(r'subjectId\s*[:=]\s*(\d+)').allMatches(text);
    for (final match in leakedIds) {
      final value = int.tryParse(match.group(1) ?? '') ?? 0;
      if (value <= 0 || seen.contains(value)) {
        continue;
      }
      seen.add(value);
      ids.add(value);
    }
    return ids;
  }

  String _stripCardDirectives(String text) {
    return text
        .replaceAll(RegExp(r'\s*\[\[CARD_IDS:\s*([0-9,\s]+)\]\]\s*'), '\n')
        .replaceAll(
          RegExp(r'\s*\[系统备注：你在这轮回复中为用户展示了以下番剧卡片：[\s\S]*?\]\s*'),
          '\n',
        )
        .trim();
  }

  Future<List<AnimeCalendarItem>> _expandSearchCandidatesIfNeeded({
    required List<AnimeCalendarItem> candidates,
    required Map<String, dynamic>? searchPayload,
  }) async {
    if (candidates.length > 1 || searchPayload == null) {
      return candidates;
    }
    final total = int.tryParse((searchPayload['total'] ?? 0).toString()) ?? 0;
    if (total <= candidates.length) {
      return candidates;
    }
    final request = searchPayload['request'];
    if (request is! Map<String, dynamic>) {
      return candidates;
    }
    final replayArguments = Map<String, dynamic>.from(request);
    final currentLimit =
        int.tryParse((replayArguments['limit'] ?? 0).toString()) ?? 0;
    if (currentLimit >= 10) {
      return candidates;
    }
    replayArguments['limit'] = 10;
    final replay =
        await _dispatcher.execute('AnimeSearchTool', replayArguments);
    if (!replay.success || replay.items.isEmpty) {
      return candidates;
    }
    return _dedupeItems(replay.items);
  }

  String _buildClarificationContinuationInstruction(
      _ClarificationSelection selection) {
    final toolName = selection.option.toolName;
    final subjectId = selection.option.subjectId ?? selection.item.id;
    if (toolName == 'AnimeControlTool') {
      final intent = selection.option.controlIntent ?? '';
      return '上一轮已确认目标作品是《${selection.item.name}》'
          '（subjectId=$subjectId），待继续的是追番列表操作。'
          '${intent.isNotEmpty ? '本次 intent=$intent。' : ''}';
    }
    if (toolName == 'AnimeCharacterTool') {
      return '上一轮已确认目标作品是《${selection.item.name}》'
          '（subjectId=$subjectId），待继续的是番剧角色查询。';
    }
    return '上一轮已确认目标作品是《${selection.item.name}》'
        '（subjectId=$subjectId），待继续的是详情查询。';
  }

  bool _shouldResolveSubjectFromSearchResults(
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    if (toolName != 'AnimeDetailTool' && toolName != 'AnimeCharacterTool') {
      return false;
    }
    return !_hasExplicitSubjectId(arguments);
  }

  bool _hasExplicitSubjectId(Map<String, dynamic> arguments) {
    final rawSubjectId = arguments['subjectId'];
    final subjectId = int.tryParse(rawSubjectId?.toString() ?? '') ?? 0;
    return subjectId > 0;
  }

  String _buildToolExecutionSignature(
      String toolName, Map<String, dynamic> arguments) {
    return '$toolName|${_stringifyDebugJson(arguments)}';
  }

  bool _shouldLockClarifiedSubject(
    String toolName,
    _ClarificationSelection? selection,
  ) {
    if (selection == null) {
      return false;
    }
    final optionToolName = selection.option.toolName;
    if (optionToolName == null || optionToolName.isEmpty) {
      return toolName == 'AnimeDetailTool' || toolName == 'AnimeCharacterTool';
    }
    return optionToolName == toolName;
  }

  AgentReply? _buildControlClarificationReply(AgentToolResult result) {
    final payload = result.payload;
    if (payload['requiresClarification'] != true) {
      return null;
    }
    final items = result.items;
    if (items.isEmpty) {
      return null;
    }
    final intent = payload['intent']?.toString().trim() ?? '';
    return AgentReply(
      text: _buildControlClarificationText(intent: intent, candidates: items),
      items: items,
      options: _buildClarificationOptions(
        items,
        toolName: 'AnimeControlTool',
        controlIntent: intent,
      ),
    );
  }

  String _buildControlClarificationText({
    required String intent,
    required List<AnimeCalendarItem> candidates,
  }) {
    final action = switch (intent) {
      'DELETE_ANIME' => '删除',
      'MARK_WATCHED' => '标记为已看完',
      'MARK_WATCHING' => '标记为在看',
      'MARK_WANT_TO_WATCH' => '标记为想看',
      'UPDATE_PROGRESS' => '更新进度',
      'TOGGLE_REMIND' => '修改提醒',
      _ => '继续操作',
    };
    final lines = <String>['星奈这边找到多个候选，暂时还不能直接$action哦，请先确认具体是哪一部：'];
    for (var i = 0; i < candidates.length; i++) {
      final item = candidates[i];
      final date = item.airDate.trim();
      lines.add('${i + 1}. ${item.name}${date.isNotEmpty ? '（$date）' : ''}');
    }
    lines.add('你可以直接点下面的选项按钮；如果没有你想要的，就点“其他”后自己输入完整作品名哦～');
    return lines.join('\n');
  }

  _ClarificationSelection? _resolveClarificationSelection(
    List<AgentMessage> history,
    String userInput,
  ) {
    final text = userInput.trim();
    if (text.isEmpty) {
      return null;
    }
    AgentMessage? source;
    for (var i = history.length - 1; i >= 0; i--) {
      final message = history[i];
      if (message.role != AgentMessageRole.assistant ||
          message.options.isEmpty) {
        continue;
      }
      source = message;
      break;
    }
    if (source == null || source.items.isEmpty) {
      return null;
    }
    final candidatesById = {
      for (final item in source.items)
        if (item.id > 0) item.id: item,
    };
    for (var index = 0; index < source.options.length; index++) {
      final option = source.options[index];
      if (option.requiresManualInput) {
        continue;
      }
      if (!_matchesClarificationInput(text, option, index)) {
        continue;
      }
      final subjectId = option.subjectId;
      final item = subjectId != null ? candidatesById[subjectId] : null;
      if (item == null) {
        continue;
      }
      return _ClarificationSelection(option: option, item: item);
    }
    return null;
  }

  bool _matchesClarificationInput(
      String input, AgentMessageOption option, int index) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (trimmed == option.label ||
        trimmed == option.value ||
        _normalizeSubjectText(trimmed) == _normalizeSubjectText(option.label) ||
        _normalizeSubjectText(trimmed) == _normalizeSubjectText(option.value)) {
      return true;
    }
    final order = index + 1;
    final chineseOrder = _numberToChinese(order);
    final normalized = trimmed.replaceAll(' ', '');
    final numericCandidates = <String>{
      '$order',
      '第$order个',
      '第$order部',
      '第$order季',
      '第$order版',
      '第$order个',
      '第$chineseOrder个',
      '第$chineseOrder部',
      '第$chineseOrder季',
      chineseOrder,
      '$order季',
      '$chineseOrder季',
      '$chineseOrder期',
    };
    if (numericCandidates.contains(normalized)) {
      return true;
    }
    return false;
  }

  String _numberToChinese(int value) {
    return switch (value) {
      1 => '一',
      2 => '二',
      3 => '三',
      4 => '四',
      5 => '五',
      6 => '六',
      7 => '七',
      8 => '八',
      9 => '九',
      10 => '十',
      _ => value.toString(),
    };
  }

  _SubjectResolution _resolveSubjectFromSearchResults({
    required String userInput,
    required List<AnimeCalendarItem> candidates,
    Map<String, dynamic>? searchPayload,
  }) {
    final deduped = _dedupeItems(candidates);
    if (deduped.length <= 1) {
      return _SubjectResolution(
        exactItem: deduped.isEmpty ? null : deduped.first,
        candidates: deduped,
        needsClarification: false,
      );
    }

    String extractedTitle = _extractLikelySubjectTitle(userInput);
    String normalizedTitle = _normalizeSubjectText(extractedTitle);

    String? searchKeyword;
    if (searchPayload != null && searchPayload['request'] is Map) {
      searchKeyword = searchPayload['request']['keyword']?.toString().trim();
    }

    if (searchKeyword != null && searchKeyword.isNotEmpty) {
      final normalizedSearch = _normalizeSubjectText(searchKeyword);
      final exactMatchesSearch = deduped.where((item) {
        return _normalizeSubjectText(item.name) == normalizedSearch;
      }).toList();
      if (exactMatchesSearch.length == 1) {
        return _SubjectResolution(
          exactItem: exactMatchesSearch.first,
          candidates: exactMatchesSearch,
          needsClarification: false,
        );
      }

      final hasQuotes = userInput.contains('《') ||
          userInput.contains('“') ||
          userInput.contains('"') ||
          userInput.contains('「');
      if (!hasQuotes && extractedTitle.length > 6) {
        extractedTitle = searchKeyword;
        normalizedTitle = normalizedSearch;
      }
    }

    if (normalizedTitle.isEmpty) {
      return _SubjectResolution(
        exactItem: null,
        candidates: deduped.take(5).toList(),
        needsClarification: true,
        extractedTitle: extractedTitle,
      );
    }

    final exactMatches = deduped.where((item) {
      return _normalizeSubjectText(item.name) == normalizedTitle;
    }).toList();
    if (exactMatches.length == 1) {
      return _SubjectResolution(
        exactItem: exactMatches.first,
        candidates: exactMatches,
        needsClarification: false,
      );
    }

    final fuzzyMatches = deduped.where((item) {
      final normalizedName = _normalizeSubjectText(item.name);
      return normalizedName.contains(normalizedTitle) ||
          normalizedTitle.contains(normalizedName);
    }).toList();
    if (fuzzyMatches.length == 1 &&
        !_looksLikeVariantEntry(fuzzyMatches.first.name, extractedTitle)) {
      return _SubjectResolution(
        exactItem: fuzzyMatches.first,
        candidates: fuzzyMatches,
        needsClarification: false,
      );
    }

    final clarificationCandidates =
        fuzzyMatches.isNotEmpty ? fuzzyMatches : deduped.take(5).toList();
    return _SubjectResolution(
      exactItem: null,
      candidates: clarificationCandidates.take(5).toList(),
      needsClarification: true,
      extractedTitle: extractedTitle,
    );
  }

  String _extractLikelySubjectTitle(String input) {
    final text = input.trim();
    final patterns = [
      RegExp(r'《([^》]+)》'),
      RegExp(r'“([^”]+)”'),
      RegExp(r'"([^"]+)"'),
      RegExp(r'「([^」]+)」'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      final value = match?.group(1)?.trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }

    var cleaned = text;
    const removablePhrases = [
      '给我',
      '帮我',
      '查一下',
      '查查',
      '告诉我',
      '我想知道',
      '角色信息',
      '角色',
      '主角',
      '配角',
      '声优',
      '编剧',
      '原作',
      '是谁',
      '有哪些',
      '有谁',
      '番剧',
      '动画',
      '动漫',
      '信息',
      '资料',
    ];
    for (final phrase in removablePhrases) {
      cleaned = cleaned.replaceAll(phrase, ' ');
    }
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  String _normalizeSubjectText(String value) {
    return value
        .toLowerCase()
        .replaceAll(
            RegExp("[\\s·:：\\-—_!！?？,，.。/／\\(\\)（）\\[\\]【】「」『』\"“”'《》]"), '')
        .trim();
  }

  bool _looksLikeVariantEntry(String candidateName, String extractedTitle) {
    final normalizedCandidate = _normalizeSubjectText(candidateName);
    final normalizedTitle = _normalizeSubjectText(extractedTitle);
    if (normalizedCandidate == normalizedTitle) {
      return false;
    }
    const variantMarkers = [
      '第二季',
      '第三季',
      '第四季',
      '第五季',
      'season2',
      'season3',
      'season4',
      '剧场版',
      '特别篇',
      '总集篇',
      'ova',
      'oad',
      'sp',
      '篇',
      '前传',
      '后篇',
      '前篇',
      '黄金乡',
    ];
    for (final marker in variantMarkers) {
      if (candidateName.contains(marker) ||
          normalizedCandidate.contains(_normalizeSubjectText(marker))) {
        return true;
      }
    }
    return false;
  }

  List<AgentMessageOption> _buildClarificationOptions(
    List<AnimeCalendarItem> candidates, {
    String? toolName,
    String? controlIntent,
  }) {
    final options = <AgentMessageOption>[];
    final usedLabels = <String>{};
    final hasSeasonVariants = candidates
        .any((item) => RegExp(r'第([一二三四五六七八九十0-9]+)季').hasMatch(item.name));
    for (var i = 0; i < candidates.length; i++) {
      final item = candidates[i];
      var label = _buildClarificationLabel(
        item,
        i,
        hasSeasonVariants: hasSeasonVariants,
      );
      if (!usedLabels.add(label)) {
        label = item.name;
        usedLabels.add(label);
      }
      options.add(
        AgentMessageOption(
          label: label,
          value: item.name,
          subjectId: item.id,
          toolName: toolName,
          controlIntent: controlIntent,
        ),
      );
    }
    options.add(
      const AgentMessageOption(
        label: '其他',
        value: '',
        requiresManualInput: true,
      ),
    );
    return options;
  }

  String _buildClarificationLabel(
    AnimeCalendarItem item,
    int index, {
    required bool hasSeasonVariants,
  }) {
    final name = item.name.trim();
    final seasonMatch = RegExp(r'第([一二三四五六七八九十0-9]+)季').firstMatch(name);
    if (seasonMatch != null) {
      return '第${seasonMatch.group(1)}季';
    }
    const markers = ['剧场版', '特别篇', '总集篇', 'OVA', 'OAD', 'SP'];
    for (final marker in markers) {
      if (name.toUpperCase().contains(marker.toUpperCase())) {
        return marker;
      }
    }
    if (index == 0 && hasSeasonVariants) {
      return '第一季';
    }
    return name;
  }
}

class _SubjectResolution {
  const _SubjectResolution({
    required this.exactItem,
    required this.candidates,
    required this.needsClarification,
    this.extractedTitle,
  });

  final AnimeCalendarItem? exactItem;
  final List<AnimeCalendarItem> candidates;
  final bool needsClarification;
  final String? extractedTitle;
}

class _ClarificationSelection {
  const _ClarificationSelection({
    required this.option,
    required this.item,
  });

  final AgentMessageOption option;
  final AnimeCalendarItem item;
}
