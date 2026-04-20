import 'dart:convert';

import 'package:drama_tracker/models/agent_message.dart';
import 'package:drama_tracker/models/anime_calendar_item.dart';

class AgentChatSession {
  const AgentChatSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAtMs,
    required this.contextBytes,
    required this.isContextFull,
  });

  final String id;
  final String title;
  final List<AgentMessage> messages;
  final int updatedAtMs;
  final int contextBytes;
  final bool isContextFull;

  AgentChatSession copyWith({
    String? id,
    String? title,
    List<AgentMessage>? messages,
    int? updatedAtMs,
    int? contextBytes,
    bool? isContextFull,
  }) {
    return AgentChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      contextBytes: contextBytes ?? this.contextBytes,
      isContextFull: isContextFull ?? this.isContextFull,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'messages': messages.map(_messageToMap).toList(),
      'updatedAtMs': updatedAtMs,
      'contextBytes': contextBytes,
      'isContextFull': isContextFull,
    };
  }

  factory AgentChatSession.fromMap(Map<String, dynamic> map) {
    final rawMessages = map['messages'];
    final parsedMessages = rawMessages is List
        ? rawMessages
            .whereType<Map>()
            .map((item) => _messageFromMap(Map<String, dynamic>.from(item)))
            .toList()
        : <AgentMessage>[];
    return AgentChatSession(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '新对话',
      messages: parsedMessages,
      updatedAtMs: int.tryParse((map['updatedAtMs'] ?? 0).toString()) ?? 0,
      contextBytes: int.tryParse((map['contextBytes'] ?? 0).toString()) ?? 0,
      isContextFull: (map['isContextFull'] ?? false).toString() == 'true',
    );
  }

  static Map<String, dynamic> _messageToMap(AgentMessage message) {
    return {
      'role': message.role.name,
      'content': message.content,
      'debugTrace': message.debugTrace,
      'createdAtMs': message.createdAt?.millisecondsSinceEpoch ?? 0,
      'items': message.items.map(_animeToMap).toList(),
      'options': message.options.map(_optionToMap).toList(),
    };
  }

  static AgentMessage _messageFromMap(Map<String, dynamic> map) {
    final roleName = map['role']?.toString() ?? AgentMessageRole.assistant.name;
    var role = AgentMessageRole.assistant;
    for (final item in AgentMessageRole.values) {
      if (item.name == roleName) {
        role = item;
        break;
      }
    }
    final rawItems = map['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((item) => _animeFromMap(Map<String, dynamic>.from(item)))
            .toList()
        : <AnimeCalendarItem>[];
    final rawOptions = map['options'];
    final options = rawOptions is List
        ? rawOptions
            .whereType<Map>()
            .map((item) => _optionFromMap(Map<String, dynamic>.from(item)))
            .toList()
        : <AgentMessageOption>[];
    final createdAtMs = int.tryParse((map['createdAtMs'] ?? 0).toString()) ?? 0;
    return AgentMessage(
      role: role,
      content: map['content']?.toString() ?? '',
      items: items,
      options: options,
      debugTrace: map['debugTrace']?.toString() ?? '',
      createdAt: createdAtMs > 0 ? DateTime.fromMillisecondsSinceEpoch(createdAtMs) : null,
    );
  }

  static Map<String, dynamic> _optionToMap(AgentMessageOption option) {
    return {
      'label': option.label,
      'value': option.value,
      'subjectId': option.subjectId ?? 0,
      'toolName': option.toolName ?? '',
      'controlIntent': option.controlIntent ?? '',
      'requiresManualInput': option.requiresManualInput,
    };
  }

  static AgentMessageOption _optionFromMap(Map<String, dynamic> map) {
    final subjectId = int.tryParse((map['subjectId'] ?? 0).toString()) ?? 0;
    return AgentMessageOption(
      label: map['label']?.toString() ?? '',
      value: map['value']?.toString() ?? '',
      subjectId: subjectId > 0 ? subjectId : null,
      toolName: (map['toolName']?.toString().trim().isNotEmpty ?? false)
          ? map['toolName']?.toString().trim()
          : null,
      controlIntent: (map['controlIntent']?.toString().trim().isNotEmpty ?? false)
          ? map['controlIntent']?.toString().trim()
          : null,
      requiresManualInput: (map['requiresManualInput'] ?? false).toString() == 'true',
    );
  }

  static Map<String, dynamic> _animeToMap(AnimeCalendarItem item) {
    return {
      'id': item.id,
      'name': item.name,
      'coverUrl': item.coverUrl,
      'airWeekday': item.airWeekday,
      'airDate': item.airDate,
      'ratingScore': item.ratingScore,
      'doingCount': item.doingCount,
      'summary': item.summary,
      'totalEpisodes': item.totalEpisodes,
    };
  }

  static AnimeCalendarItem _animeFromMap(Map<String, dynamic> map) {
    final rating = double.tryParse((map['ratingScore'] ?? 0).toString()) ?? 0;
    return AnimeCalendarItem(
      id: int.tryParse((map['id'] ?? 0).toString()) ?? 0,
      name: map['name']?.toString() ?? '未知番剧',
      coverUrl: map['coverUrl']?.toString() ?? '',
      airWeekday: int.tryParse((map['airWeekday'] ?? 0).toString()) ?? 0,
      airDate: map['airDate']?.toString() ?? '',
      ratingScore: rating,
      doingCount: int.tryParse((map['doingCount'] ?? 0).toString()) ?? 0,
      summary: map['summary']?.toString() ?? '',
      totalEpisodes: int.tryParse((map['totalEpisodes'] ?? 0).toString()) ?? 0,
    );
  }
}

int calculateAgentContextBytes(List<AgentMessage> messages) {
  var total = 0;
  for (final message in messages) {
    total += utf8.encode(message.role.name).length;
    total += utf8.encode(message.content).length;
    total += utf8.encode(message.debugTrace).length;
    for (final option in message.options) {
      total += utf8.encode(option.label).length;
      total += utf8.encode(option.value).length;
    }
  }
  return total;
}
