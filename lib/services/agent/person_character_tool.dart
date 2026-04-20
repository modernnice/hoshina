import 'package:drama_tracker/services/agent/agent_models.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';

class PersonCharacterTool extends AgentTool {
  PersonCharacterTool(this._apiService);

  final BangumiApiService _apiService;

  @override
  String get name => 'PersonCharacterTool';

  @override
  String get description => '根据现实人物 personId 查询与其相关的角色，最常用于根据声优 id 查询配音过哪些角色。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'personId': {'type': 'integer', 'description': 'Bangumi person_id'},
          'limit': {'type': 'integer', 'description': '最多返回多少个角色，默认 12'},
        },
        'required': ['personId'],
      };

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> input) async {
    final personId = int.tryParse(input['personId']?.toString() ?? '') ?? 0;
    if (personId <= 0) {
      return const AgentToolResult(
        success: false,
        message: 'personId 无效，无法查询人物相关角色',
      );
    }
    final limit =
        (int.tryParse(input['limit']?.toString() ?? '') ?? 12).clamp(1, 30);
    try {
      final characters =
          await _apiService.fetchPersonRelatedCharacters(personId);
      final selected = characters.take(limit).toList();
      return AgentToolResult(
        success: true,
        message: selected.isEmpty
            ? '暂时没有查到该人物相关的角色'
            : '已找到 ${selected.length} 个相关角色',
        payload: {
          'personId': personId,
          'count': selected.length,
          'characters': selected
              .map((character) => {
                    'id': character.id,
                    'name': character.displayName,
                    'originName': character.name,
                    'relation': character.relation,
                    'summary': character.summary,
                    'subjects': character.subjects
                        .map((subject) => {
                              'id': subject.id,
                              'name': subject.displayName,
                              'originName': subject.name,
                              'staff': subject.staff,
                            })
                        .toList(),
                  })
              .toList(),
        },
      );
    } catch (e) {
      return AgentToolResult(success: false, message: '人物相关角色查询失败：$e');
    }
  }
}
