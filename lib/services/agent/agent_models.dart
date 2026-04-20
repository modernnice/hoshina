import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/models/agent_message.dart';

class AgentToolResult {
  const AgentToolResult({
    required this.success,
    required this.message,
    this.items = const [],
    this.payload = const {},
  });

  final bool success;
  final String message;
  final List<AnimeCalendarItem> items;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'count': items.length,
      'items': items
          .take(10)
          .map((e) => {
                'id': e.id,
                'name': e.name,
                'score': e.ratingScore,
                'doingCount': e.doingCount,
                'airDate': e.airDate,
                'summary': e.summary,
              })
          .toList(),
      'payload': payload,
    };
  }
}

abstract class AgentTool {
  String get name;
  String get description;
  Map<String, dynamic> get parametersSchema;

  Map<String, dynamic> toFunctionToolJson() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': parametersSchema,
      }
    };
  }

  Future<AgentToolResult> execute(Map<String, dynamic> input);
}

class AgentReply {
  const AgentReply({
    required this.text,
    this.items = const [],
    this.options = const [],
    this.debugTrace = '',
  });

  final String text;
  final List<AnimeCalendarItem> items;
  final List<AgentMessageOption> options;
  final String debugTrace;
}
