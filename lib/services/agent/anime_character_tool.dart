import 'package:drama_tracker/models/anime_detail.dart';
import 'package:drama_tracker/services/agent/agent_models.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';

class AnimeCharacterTool extends AgentTool {
  AnimeCharacterTool(this._apiService);

  final BangumiApiService _apiService;

  @override
  String get name => 'AnimeCharacterTool';

  @override
  String get description =>
      '获取某部番剧的角色与声优列表。只接受 subjectId，用于回答“这部番有哪些角色/主角是谁/配音是谁”等问题。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'subjectId': {'type': 'integer', 'description': 'Bangumi subject_id'},
          'limit': {'type': 'integer', 'description': '最多返回多少位角色，默认 8'},
        },
        'required': ['subjectId'],
      };

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> input) async {
    final id = int.tryParse(input['subjectId']?.toString() ?? '') ?? 0;
    if (id <= 0) {
      return const AgentToolResult(
        success: false,
        message: 'subjectId 无效，无法获取这部番剧的角色信息',
      );
    }
    final limit = (int.tryParse(input['limit']?.toString() ?? '') ?? 8).clamp(1, 20);
    try {
      final characters = await _apiService.fetchSubjectCharacters(id);
      final sorted = [...characters]..sort(AnimeCharacter.compareByRolePriority);
      final selected = sorted.take(limit).toList();
      return AgentToolResult(
        success: true,
        message: selected.isEmpty ? '暂时没有查到这部番的角色信息' : '已获取这部番的 ${selected.length} 位角色信息',
        payload: {
          'subjectId': id,
          'count': selected.length,
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
      return AgentToolResult(success: false, message: '角色信息获取失败：$e');
    }
  }
}
