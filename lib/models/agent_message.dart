import 'package:drama_tracker/models/anime_calendar_item.dart';

enum AgentMessageRole { user, assistant, system }

class AgentMessageOption {
  const AgentMessageOption({
    required this.label,
    required this.value,
    this.subjectId,
    this.toolName,
    this.controlIntent,
    this.requiresManualInput = false,
  });

  final String label;
  final String value;
  final int? subjectId;
  final String? toolName;
  final String? controlIntent;
  final bool requiresManualInput;

  AgentMessageOption copyWith({
    String? label,
    String? value,
    int? subjectId,
    String? toolName,
    String? controlIntent,
    bool? requiresManualInput,
  }) {
    return AgentMessageOption(
      label: label ?? this.label,
      value: value ?? this.value,
      subjectId: subjectId ?? this.subjectId,
      toolName: toolName ?? this.toolName,
      controlIntent: controlIntent ?? this.controlIntent,
      requiresManualInput: requiresManualInput ?? this.requiresManualInput,
    );
  }
}

class AgentMessage {
  const AgentMessage({
    required this.role,
    required this.content,
    this.items = const [],
    this.options = const [],
    this.debugTrace = '',
    this.createdAt,
  });

  final AgentMessageRole role;
  final String content;
  final List<AnimeCalendarItem> items;
  final List<AgentMessageOption> options;
  final String debugTrace;
  final DateTime? createdAt;

  AgentMessage copyWith({
    AgentMessageRole? role,
    String? content,
    List<AnimeCalendarItem>? items,
    List<AgentMessageOption>? options,
    String? debugTrace,
    DateTime? createdAt,
  }) {
    return AgentMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      items: items ?? this.items,
      options: options ?? this.options,
      debugTrace: debugTrace ?? this.debugTrace,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
