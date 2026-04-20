import 'package:drama_tracker/services/agent/agent_models.dart';

class CurrentTimeTool extends AgentTool {
  @override
  String get name => 'CurrentTimeTool';

  @override
  String get description => '获取设备当前时间与时区信息，用于计算“最新/本季/最近”相关时间范围。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {},
      };

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> input) async {
    final now = DateTime.now();
    final utc = now.toUtc();
    return AgentToolResult(
      success: true,
      message: '当前时间：${now.toIso8601String()}（${now.timeZoneName}）',
      payload: {
        'nowIso': now.toIso8601String(),
        'utcIso': utc.toIso8601String(),
        'timezoneName': now.timeZoneName,
        'timezoneOffsetMinutes': now.timeZoneOffset.inMinutes,
        'date':
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      },
    );
  }
}
