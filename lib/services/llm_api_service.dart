import 'dart:convert';

import 'package:drama_tracker/models/llm_config.dart';
import 'package:http/http.dart' as http;

class LlmToolCall {
  const LlmToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class LlmChatResponse {
  const LlmChatResponse({
    required this.content,
    required this.toolCalls,
    this.rawResponse = const {},
  });

  final String content;
  final List<LlmToolCall> toolCalls;
  final Map<String, dynamic> rawResponse;
}

class LlmApiService {
  bool _isMiniMaxConfig(LlmConfig config) {
    final url = config.llmUrl.trim().toLowerCase();
    final model = config.llmName.trim().toLowerCase();
    return url.contains('minimax') || model.startsWith('minimax-');
  }

  bool _isKimiConfig(LlmConfig config) {
    final url = config.llmUrl.trim().toLowerCase();
    final model = config.llmName.trim().toLowerCase();
    return url.contains('moonshot') || model.startsWith('kimi-');
  }

  num _resolveTemperature(LlmConfig config) {
    if (_isKimiConfig(config)) {
      return 1;
    }
    return 0.2;
  }

  List<Map<String, dynamic>> _normalizeMessagesForProvider(
    LlmConfig config,
    List<Map<String, dynamic>> messages,
  ) {
    if (!_isMiniMaxConfig(config)) {
      return messages;
    }

    final systemContents = <String>[];
    final normalized = <Map<String, dynamic>>[];
    for (final message in messages) {
      final role = message['role']?.toString();
      final content = message['content']?.toString().trim() ?? '';
      if (role == 'system') {
        if (content.isNotEmpty) {
          systemContents.add(content);
        }
        continue;
      }
      normalized.add(Map<String, dynamic>.from(message));
    }

    if (systemContents.isNotEmpty) {
      normalized.insert(0, {
        'role': 'system',
        'content': systemContents.join('\n\n'),
      });
    }
    return normalized;
  }

  Uri _buildChatCompletionUri(String rawUrl) {
    final parsed = Uri.parse(rawUrl.trim());
    final normalizedPath = parsed.path.endsWith('/')
        ? parsed.path.substring(0, parsed.path.length - 1)
        : parsed.path;
    final lowerPath = normalizedPath.toLowerCase();
    if (lowerPath.endsWith('/chat/completions')) {
      return parsed;
    }
    final nextPath = normalizedPath.isEmpty
        ? '/chat/completions'
        : '$normalizedPath/chat/completions';
    return parsed.replace(path: nextPath);
  }

  Future<LlmChatResponse> chatCompletions({
    required LlmConfig config,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async {
    final uri = _buildChatCompletionUri(config.llmUrl);
    final normalizedMessages = _normalizeMessagesForProvider(config, messages);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (config.llmKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.llmKey.trim()}';
    }
    final body = <String, dynamic>{
      'model': config.llmName.trim(),
      'messages': normalizedMessages,
      'temperature': _resolveTemperature(config),
    };
    if (tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] = 'auto';
    }
    final response = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('LLM 请求失败：${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('LLM 返回格式错误');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map<String, dynamic>) {
      throw Exception('LLM 返回缺少 choices');
    }
    final message = (choices.first as Map<String, dynamic>)['message'];
    if (message is! Map<String, dynamic>) {
      throw Exception('LLM 返回缺少 message');
    }
    final content = message['content']?.toString() ?? '';
    final parsedToolCalls = <LlmToolCall>[];
    final rawToolCalls = message['tool_calls'];
    if (rawToolCalls is List) {
      for (final call in rawToolCalls) {
        if (call is! Map<String, dynamic>) {
          continue;
        }
        final functionObj = call['function'];
        if (functionObj is! Map<String, dynamic>) {
          continue;
        }
        final name = functionObj['name']?.toString() ?? '';
        final argsText = functionObj['arguments']?.toString() ?? '{}';
        if (name.isEmpty) {
          continue;
        }
        Map<String, dynamic> args = {};
        try {
          final decodedArgs = jsonDecode(argsText);
          if (decodedArgs is Map<String, dynamic>) {
            args = decodedArgs;
          }
        } catch (_) {
          args = {};
        }
        parsedToolCalls.add(
          LlmToolCall(
            id: call['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            arguments: args,
          ),
        );
      }
    }
    return LlmChatResponse(
      content: content,
      toolCalls: parsedToolCalls,
      rawResponse: decoded,
    );
  }
}
