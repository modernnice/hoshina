import 'package:drama_tracker/models/agent_chat_session.dart';
import 'package:drama_tracker/models/agent_message.dart';
import 'package:hive/hive.dart';

class AgentChatHistoryStorage {
  AgentChatHistoryStorage() : _box = Hive.box<Map>(_boxName);

  static const String _boxName = 'agent_chat_sessions';
  static const String _prefix = 'session_';

  final Box<Map> _box;

  String get storagePath =>
      _box.path ?? '应用私有目录/Hive/agent_chat_sessions';

  List<AgentChatSession> loadAllSessions() {
    final sessions = _box.keys
        .whereType<String>()
        .where((key) => key.startsWith(_prefix))
        .map((key) {
      final value = _box.get(key);
      if (value == null) {
        return null;
      }
      final map = Map<String, dynamic>.from(value);
      final session = AgentChatSession.fromMap(map);
      if (session.id.isEmpty) {
        return null;
      }
      return session;
    }).whereType<AgentChatSession>().toList();

    sessions.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return sessions;
  }

  Future<void> saveSession(AgentChatSession session) async {
    await _box.put('$_prefix${session.id}', session.toMap());
  }

  Future<void> deleteSession(String sessionId) async {
    await _box.delete('$_prefix$sessionId');
  }

  AgentChatSession createSession({
    required String id,
    required String title,
    required List<AgentMessage> messages,
    bool isContextFull = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return AgentChatSession(
      id: id,
      title: title,
      messages: List<AgentMessage>.from(messages),
      updatedAtMs: now,
      contextBytes: calculateAgentContextBytes(messages),
      isContextFull: isContextFull,
    );
  }
}
