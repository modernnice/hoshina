import 'package:drama_tracker/services/agent/agent_models.dart';
import 'package:drama_tracker/services/agent/anime_recommendation_support.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';

class GetUserPreferenceSeedsTool extends AgentTool {
  GetUserPreferenceSeedsTool(
    BangumiApiService apiService,
    WatchlistStorage storage,
  ) : _support = AnimeRecommendationSupport(apiService, storage);

  final AnimeRecommendationSupport _support;

  @override
  String get name => 'GetUserPreferenceSeeds';

  @override
  String get description =>
      '获取用户追番中权重最高的8个不同系列作品（种子），每个种子附带与预定义词表匹配的标签。同时返回全局偏好标签列表（按权重降序）。无参数。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': <String, dynamic>{},
      };

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> input) async {
    final rankedPreferences = _support.getRankedPreferences();
    if (rankedPreferences.isEmpty) {
      return const AgentToolResult(
          success: false, message: '暂无足够追番数据，建议先添加或评分一些番剧');
    }

    final seeds = _support.selectTitleSeeds(rankedPreferences, limit: 8);
    final allPreferenceTags = await _support.extractPreferenceTags(
      seeds,
      fallbackProgresses: rankedPreferences,
    );
    final seedPayload = <Map<String, dynamic>>[];
    for (final seed in seeds) {
      final tags = await _support.loadCanonicalTags(
        progress: seed,
        vocabularyList: AnimeRecommendationSupport.vocabulary,
      );
      seedPayload.add({
        'subject_id': seed.subjectId,
        'name': seed.name.trim(),
        'weight':
            double.parse(_support.preferenceWeight(seed).toStringAsFixed(2)),
        'tags': tags.toList()..sort(),
      });
    }

    return AgentToolResult(
      success: true,
      message:
          '已提取 ${seedPayload.length} 个偏好种子，并整理出 ${allPreferenceTags.length} 个偏好标签',
      payload: {
        'seeds': seedPayload,
        'all_preference_tags': allPreferenceTags,
      },
    );
  }
}
