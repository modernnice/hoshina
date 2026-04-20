import 'package:drama_tracker/services/agent/agent_models.dart';

class AgentDispatcher {
  AgentDispatcher({
    required List<AgentTool> tools,
  }) : _tools = {for (final t in tools) t.name: t};

  final Map<String, AgentTool> _tools;

  List<Map<String, dynamic>> buildToolSchemas() {
    return _tools.values.map((e) => e.toFunctionToolJson()).toList();
  }

  Future<AgentToolResult> execute(String toolName, Map<String, dynamic> input) async {
    final tool = _tools[toolName];
    if (tool == null) {
      return AgentToolResult(success: false, message: '未注册的 Tool：$toolName');
    }
    return tool.execute(input);
  }
}
