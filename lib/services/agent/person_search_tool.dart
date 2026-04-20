import 'package:drama_tracker/services/agent/agent_models.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';

class PersonSearchTool extends AgentTool {
  PersonSearchTool(this._apiService);

  final BangumiApiService _apiService;

  @override
  String get name => 'PersonSearchTool';

  @override
  String get description =>
      '检索现实中的人物，包括导演、编剧、声优等从业者。只接受人物关键词，不用于搜索角色或番剧。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'keyword': {'type': 'string', 'description': '人物关键词，如 花江夏树 / 新海诚'},
          'career': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '职业筛选，可传 seiyu / director / writer / artist 等',
          },
          'limit': {'type': 'integer', 'description': '最多返回多少位人物，默认 8'},
          'offset': {'type': 'integer', 'description': '分页偏移，默认 0'},
        },
        'required': ['keyword'],
      };

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> input) async {
    final keyword = input['keyword']?.toString().trim() ?? '';
    if (keyword.isEmpty) {
      return const AgentToolResult(
        success: false,
        message: 'keyword 不能为空，无法搜索人物',
      );
    }
    final limit = (int.tryParse(input['limit']?.toString() ?? '') ?? 8).clamp(1, 20);
    final offset = int.tryParse(input['offset']?.toString() ?? '') ?? 0;
    final careers = <String>[];
    final rawCareers = input['career'];
    if (rawCareers is List) {
      for (final item in rawCareers) {
        final value = item?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          careers.add(value);
        }
      }
    }
    try {
      final page = await _apiService.searchPersons(
        keyword: keyword,
        limit: limit,
        offset: offset,
        careers: careers,
      );
      final selected = page.data.take(limit).toList();
      return AgentToolResult(
        success: true,
        message: selected.isEmpty ? '暂时没有查到相关人物' : '已找到 ${selected.length} 位相关人物',
        payload: {
          'keyword': keyword,
          'count': selected.length,
          'total': page.total,
          'request': page.request,
          'persons': selected
              .map((person) => {
                    'id': person.id,
                    'name': person.displayName,
                    'originName': person.name,
                    'careers': person.careers,
                    'summary': person.summary,
                    'image': person.imageUrl,
                  })
              .toList(),
        },
      );
    } catch (e) {
      return AgentToolResult(success: false, message: '人物搜索失败：$e');
    }
  }
}
