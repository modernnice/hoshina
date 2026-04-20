import 'package:drama_tracker/services/agent/agent_models.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';

class CharacterSearchTool extends AgentTool {
  CharacterSearchTool(this._apiService);

  final BangumiApiService _apiService;

  @override
  String get name => 'CharacterSearchTool';

  @override
  String get description =>
      '按角色名搜索角色。只接受 keyword，不用于查询某部番剧的角色列表。用于回答“介绍一下无惨这个角色”“搜索某个角色”等问题。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'keyword': {'type': 'string', 'description': '角色关键词，如 无惨 / 阿尼亚'},
          'limit': {'type': 'integer', 'description': '最多返回多少位角色，默认 8'},
          'offset': {'type': 'integer', 'description': '分页偏移，默认 0'},
          'nsfw': {'type': 'boolean', 'description': '角色搜索时是否包含 NSFW'},
        },
        'required': ['keyword'],
      };

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> input) async {
    final keyword = input['keyword']?.toString().trim() ?? '';
    if (keyword.isEmpty) {
      return const AgentToolResult(
        success: false,
        message: 'keyword 不能为空，无法搜索角色',
      );
    }
    final limit = (int.tryParse(input['limit']?.toString() ?? '') ?? 8).clamp(1, 20);
    final offset = int.tryParse(input['offset']?.toString() ?? '') ?? 0;
    try {
      final page = await _apiService.searchCharacters(
        keyword: keyword,
        limit: limit,
        offset: offset,
        nsfw: input['nsfw'] is bool ? input['nsfw'] as bool : null,
      );
      final selected = page.data.take(limit).toList();
      return AgentToolResult(
        success: true,
        message: selected.isEmpty ? '暂时没有查到相关角色' : '已找到 ${selected.length} 位相关角色',
        payload: {
          'keyword': keyword,
          'count': selected.length,
          'total': page.total,
          'request': page.request,
          'characters': selected
              .map((character) => {
                    'id': character.id,
                    'name': character.displayName,
                    'originName': character.name,
                    'relation': character.relation,
                    'summary': character.summary,
                    'actors': character.actors
                        .take(3)
                        .map((actor) => {
                              'id': actor.id,
                              'name': actor.displayName,
                              'careers': actor.careers,
                            })
                        .toList(),
                  })
              .toList(),
        },
      );
    } catch (e) {
      return AgentToolResult(success: false, message: '角色搜索失败：$e');
    }
  }
}
