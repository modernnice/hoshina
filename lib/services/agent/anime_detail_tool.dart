import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/services/agent/agent_models.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';

class AnimeDetailTool extends AgentTool {
  AnimeDetailTool(this._apiService);

  final BangumiApiService _apiService;

  @override
  String get name => 'AnimeDetailTool';

  @override
  String get description => '获取番剧详情（简介、评分、播出时间、集数等），用于回答“介绍/简介/剧情”等问题。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'subjectId': {'type': 'integer', 'description': 'Bangumi subject_id'},
        },
        'required': ['subjectId'],
      };

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> input) async {
    final id = int.tryParse(input['subjectId']?.toString() ?? '') ?? 0;
    if (id <= 0) {
      return const AgentToolResult(success: false, message: 'subjectId 无效，无法获取详情');
    }
    try {
      final detail = await _apiService.fetchSubjectDetail(id);
      final summary = detail.summary.trim();
      final title = detail.name.trim().isNotEmpty ? detail.name.trim() : '未知番剧';
      final airDate = detail.airDate.trim();
      final score = detail.ratingScore;
      final rank = detail.ratingRank;
      final totalEpisodes = detail.totalEpisodes;
      final platform = detail.platform;
      final item = AnimeCalendarItem(
        id: detail.id,
        name: title,
        coverUrl: detail.coverUrl,
        airWeekday: detail.airWeekday,
        airDate: airDate,
        ratingScore: score,
        doingCount: detail.collectionDoing,
        summary: summary,
        totalEpisodes: totalEpisodes,
      );
      return AgentToolResult(
        success: true,
        message: '已获取《$title》详情',
        items: [item],
        payload: {
          'id': detail.id,
          'name': title,
          'airDate': airDate,
          'platform': platform,
          'score': score,
          'rank': rank,
          'totalEpisodes': totalEpisodes,
          'summary': summary,
          'tags': detail.tags,
          'metaTags': detail.metaTags,
          'infobox': detail.infobox
              .map(
                (entry) => {
                  'key': entry.key,
                  'value': entry.value,
                },
              )
              .toList(),
        },
      );
    } catch (e) {
      return AgentToolResult(success: false, message: '详情获取失败：$e');
    }
  }
}
