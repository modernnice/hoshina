import 'package:drama_tracker/models/agent_message.dart';
import 'package:drama_tracker/models/agent_chat_session.dart';
import 'package:drama_tracker/screens/agent/llm_settings_page.dart';
import 'package:drama_tracker/screens/anime_detail_page.dart';
import 'package:drama_tracker/services/agent/agent_chat_history_storage.dart';
import 'package:drama_tracker/services/agent/agent_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class AgentChatPage extends StatefulWidget {
  const AgentChatPage({super.key});

  @override
  State<AgentChatPage> createState() => _AgentChatPageState();
}

class _AgentChatPageState extends State<AgentChatPage> {
  static const int _maxSavedSessions = 10;
  static const int _maxContextBytes = 1024 * 1024;

  final _service = AgentService();
  final _historyStorage = AgentChatHistoryStorage();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();

  List<AgentChatSession> _sessions = [];
  List<AgentMessage> _messages = [];
  String? _currentSessionId;
  bool _loading = true;
  bool _sending = false;
  String? _runtimeStatusText;
  String? _latestAssistantRuntimeText;
  int? _latestAssistantRuntimeIndex;

  bool get _showAgentDebugTrace {
    return _service.currentConfig?.enableAgentDebugTrace == true;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LlmSettingsPage()),
    );
  }

  Future<void> _bootstrap() async {
    final loaded = _historyStorage.loadAllSessions();
    if (loaded.isEmpty) {
      final created = _historyStorage.createSession(
        id: _nextSessionId(),
        title: _buildDefaultSessionTitle(),
        messages: [_buildWelcomeMessage()],
      );
      await _historyStorage.saveSession(created);
      loaded.add(created);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _sessions = loaded;
      _currentSessionId = loaded.first.id;
      _messages = List<AgentMessage>.from(loaded.first.messages);
      _loading = false;
    });
    _scrollToBottom();
  }

  AgentMessage _buildWelcomeMessage() {
    return AgentMessage(
      role: AgentMessageRole.assistant,
      content: '''
星奈是你的二次元追番助手 `Hoshina`。

可以直接找星奈：
- 搜番、查详情、看角色和声优
- 查导演、编剧、声优等人物信息
- 按你的口味推荐新番
- 管理想看 / 在看 / 看完和追番进度

比如：
- “推荐几部恋爱校园番”
- “介绍一下《孤独摇滚》”
- “这部番有哪些角色和声优”
- “找一下新海诚”
- “把柯南标记为已看完”

只要和追番有关，直接告诉星奈就好～
''',
      createdAt: DateTime.now(),
    );
  }

  String _nextSessionId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  String _buildDefaultSessionTitle() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '新对话 $hour:$minute';
  }

  String _extractTitleFromInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return _buildDefaultSessionTitle();
    }
    if (trimmed.length <= 16) {
      return trimmed;
    }
    return '${trimmed.substring(0, 16)}...';
  }

  AgentChatSession? _currentSession() {
    final id = _currentSessionId;
    if (id == null) {
      return null;
    }
    for (final session in _sessions) {
      if (session.id == id) {
        return session;
      }
    }
    return null;
  }

  Future<void> _persistCurrentSession({
    String? titleOverride,
    bool? isContextFull,
  }) async {
    final current = _currentSession();
    if (current == null) {
      return;
    }
    final updated = current.copyWith(
      title: titleOverride ?? current.title,
      messages: List<AgentMessage>.from(_messages),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      contextBytes: calculateAgentContextBytes(_messages),
      isContextFull: isContextFull ?? current.isContextFull,
    );
    await _historyStorage.saveSession(updated);
    if (!mounted) {
      return;
    }
    setState(() {
      _sessions = _sessions
          .map((session) => session.id == updated.id ? updated : session)
          .toList()
        ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    });
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(1)} KB';
  }

  String _formatSeconds(Duration duration) {
    final seconds = duration.inMilliseconds / 1000;
    return seconds.toStringAsFixed(1);
  }

  Future<void> _copyText(String text, {required String successHint}) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: normalized));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(successHint)),
    );
  }

  String _buildMessageCopyText(AgentMessage message) {
    final segments = <String>[message.content.trim()];
    if (message.items.isNotEmpty) {
      final cards = message.items
          .asMap()
          .entries
          .map((entry) =>
              '${entry.key + 1}. ${entry.value.name} (subjectId: ${entry.value.id})')
          .join('\n');
      segments.add('关联卡片:\n$cards');
    }
    if (message.options.isNotEmpty) {
      final options =
          message.options.map((option) => '- ${option.label}').join('\n');
      segments.add('可选操作:\n$options');
    }
    if (_showAgentDebugTrace && message.debugTrace.trim().isNotEmpty) {
      segments.add('执行轨迹与调试诊断:\n${message.debugTrace.trim()}');
    }
    return segments.where((item) => item.trim().isNotEmpty).join('\n\n');
  }

  String _toolDisplayName(String toolName) {
    switch (toolName) {
      case 'CurrentTimeTool':
        return '当前时间获取';
      case 'AnimeSearchTool':
        return '番剧检索';
      case 'AnimeDetailTool':
        return '番剧详情查询';
      case 'PersonSearchTool':
        return '人物搜索';
      case 'PersonCharacterTool':
        return '人物关联角色查询';
      case 'CharacterSearchTool':
        return '角色搜索';
      case 'AnimeCharacterTool':
        return '番剧角色查询';
      case 'GetUserPreferenceSeeds':
        return '偏好种子提取';
      case 'AnimeRecommendTool':
        return '番剧推荐';
      case 'AnimeControlTool':
        return '追番状态操作';
      default:
        return '工具调用';
    }
  }

  String _buildToolChainStatus(List<String> chain) {
    if (chain.isEmpty) {
      return '星奈正在准备中：先让星奈想一下该从哪里开始～';
    }
    final mapped = chain.map(_toolDisplayName).toList();
    return '星奈正在进行：${mapped.join(' -> ')}';
  }

  Future<void> _createNewSession() async {
    if (_sending) {
      return;
    }
    if (_sessions.length >= _maxSavedSessions) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('历史会话已经满 10 条啦，先删除一条旧会话再新建吧～')),
      );
      return;
    }
    final created = _historyStorage.createSession(
      id: _nextSessionId(),
      title: _buildDefaultSessionTitle(),
      messages: [_buildWelcomeMessage()],
    );
    await _historyStorage.saveSession(created);
    if (!mounted) {
      return;
    }
    setState(() {
      _sessions = [created, ..._sessions];
      _currentSessionId = created.id;
      _messages = List<AgentMessage>.from(created.messages);
    });
    _scrollToBottom();
  }

  void _selectSession(String sessionId) {
    if (_sending) {
      return;
    }
    AgentChatSession? selected;
    for (final session in _sessions) {
      if (session.id == sessionId) {
        selected = session;
        break;
      }
    }
    if (selected == null) {
      return;
    }
    setState(() {
      _currentSessionId = selected!.id;
      _messages = List<AgentMessage>.from(selected.messages);
    });
    _scrollToBottom();
    Navigator.of(context).pop();
  }

  Future<void> _deleteSession(String sessionId) async {
    if (_sending) {
      return;
    }
    await _historyStorage.deleteSession(sessionId);
    if (!mounted) {
      return;
    }
    var updated =
        _sessions.where((session) => session.id != sessionId).toList();
    if (updated.isEmpty) {
      final created = _historyStorage.createSession(
        id: _nextSessionId(),
        title: _buildDefaultSessionTitle(),
        messages: [_buildWelcomeMessage()],
      );
      await _historyStorage.saveSession(created);
      updated = [created];
    }
    final currentExists =
        updated.any((session) => session.id == _currentSessionId);
    final next = currentExists ? _currentSessionId : updated.first.id;
    AgentChatSession? target;
    for (final session in updated) {
      if (session.id == next) {
        target = session;
        break;
      }
    }
    setState(() {
      _sessions = updated
        ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      _currentSessionId = target?.id;
      _messages =
          target == null ? [] : List<AgentMessage>.from(target.messages);
    });
  }

  bool _willContextOverflow(AgentMessage nextMessage) {
    final nextMessages = [..._messages, nextMessage];
    return calculateAgentContextBytes(nextMessages) > _maxContextBytes;
  }

  void _showContextLimitHint() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前会话上下文已满 1MB 啦，请新建对话继续和星奈聊天～')),
    );
  }

  bool _isCurrentSessionContextFull() {
    final current = _currentSession();
    return current?.isContextFull == true;
  }

  Future<void> _send() async {
    await _sendText(_inputController.text.trim());
  }

  Future<void> _sendText(String text) async {
    if (text.isEmpty || _sending || _loading) {
      return;
    }
    if (_isCurrentSessionContextFull()) {
      _showContextLimitHint();
      return;
    }
    final userMessage = AgentMessage(
      role: AgentMessageRole.user,
      content: text,
      createdAt: DateTime.now(),
    );
    if (_willContextOverflow(userMessage)) {
      await _persistCurrentSession(isContextFull: true);
      _showContextLimitHint();
      return;
    }
    final current = _currentSession();
    final isFirstUserInput =
        _messages.where((e) => e.role == AgentMessageRole.user).isEmpty;
    final nextTitle =
        (current != null && isFirstUserInput && current.title.startsWith('新对话'))
            ? _extractTitleFromInput(text)
            : null;

    setState(() {
      _sending = true;
      _messages.add(userMessage);
      _inputController.clear();
      _runtimeStatusText = '星奈正在准备中：先让星奈想一下该从哪里开始～';
      _latestAssistantRuntimeText = null;
      _latestAssistantRuntimeIndex = null;
    });
    await _persistCurrentSession(titleOverride: nextTitle);
    _scrollToBottom();
    final stopwatch = Stopwatch()..start();
    try {
      final reply = await _service.chat(
        userInput: text,
        history: _messages,
        onToolChainUpdate: (chain) {
          if (!mounted || chain.isEmpty) {
            return;
          }
          setState(() {
            _runtimeStatusText = _buildToolChainStatus(chain);
          });
        },
      );
      if (!mounted) {
        return;
      }
      stopwatch.stop();
      setState(() {
        _messages.add(
          AgentMessage(
            role: AgentMessageRole.assistant,
            content: reply.text,
            items: reply.items,
            options: reply.options,
            debugTrace: reply.debugTrace,
            createdAt: DateTime.now(),
          ),
        );
        _latestAssistantRuntimeIndex = _messages.length - 1;
        _latestAssistantRuntimeText =
            '花费 ${_formatSeconds(stopwatch.elapsed)} 秒';
        _runtimeStatusText = null;
      });
      _scrollToBottom();
      final isFull = calculateAgentContextBytes(_messages) > _maxContextBytes;
      await _persistCurrentSession(isContextFull: isFull);
      if (isFull) {
        _showContextLimitHint();
      }
    } catch (e) {
      stopwatch.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          AgentMessage(
            role: AgentMessageRole.assistant,
            content: '好像出现了一点小问题：$e\n星奈可以再试一次，或者你换个说法告诉星奈也可以～',
            createdAt: DateTime.now(),
          ),
        );
        _latestAssistantRuntimeIndex = _messages.length - 1;
        _latestAssistantRuntimeText =
            '花费 ${_formatSeconds(stopwatch.elapsed)} 秒';
        _runtimeStatusText = null;
      });
      final isFull = calculateAgentContextBytes(_messages) > _maxContextBytes;
      await _persistCurrentSession(isContextFull: isFull);
      if (isFull) {
        _showContextLimitHint();
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _handleOptionTap(AgentMessageOption option) async {
    if (option.requiresManualInput) {
      _inputController.clear();
      _inputFocusNode.requestFocus();
      return;
    }
    await _sendText(option.label);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final currentContextBytes = calculateAgentContextBytes(_messages);
    final canSend = !_sending && !_isCurrentSessionContextFull();
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                title: Text('历史会话 (${_sessions.length}/$_maxSavedSessions)'),
                trailing: IconButton(
                  onPressed: _createNewSession,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: '新建会话',
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    final selected = session.id == _currentSessionId;
                    return ListTile(
                      selected: selected,
                      selectedTileColor: const Color(0xFFE8F4FF),
                      title: Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_formatTime(session.updatedAtMs)}  ·  ${_formatBytes(session.contextBytes)} / 1MB'
                        '${session.isContextFull ? '  ·  已满' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        onPressed: () => _deleteSession(session.id),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除',
                      ),
                      onTap: () => _selectSession(session.id),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: Text(
                  '消息只保存在这台设备本地，不会上传到服务器，换机后不会保留。',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                        fontSize: 11,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        leading: Builder(
          builder: (context) {
            return IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
              tooltip: '历史会话',
            );
          },
        ),
        title: const Text('星奈Hoshina'),
        actions: [
          IconButton(
            onPressed: _createNewSession,
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: '新建对话',
          ),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_rounded),
            tooltip: '模型设置',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: '退出',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              itemCount: _messages.length +
                  ((_sending && _runtimeStatusText != null) ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _messages.length) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            color: const Color(0xFFF8FAFC),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              child: Text(
                                _runtimeStatusText ?? '星奈正在准备中：先让星奈想一下该从哪里开始～',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFF94A3B8),
                                      fontSize: 11,
                                    ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 6, top: 1),
                            child: IconButton(
                              tooltip: '复制状态',
                              visualDensity: VisualDensity.compact,
                              iconSize: 16,
                              constraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 28),
                              padding: EdgeInsets.zero,
                              onPressed: () => _copyText(
                                _runtimeStatusText ?? '星奈正在准备中：先让星奈想一下该从哪里开始～',
                                successHint: '运行状态已复制',
                              ),
                              icon: const Icon(Icons.copy_rounded,
                                  color: Color(0xFF94A3B8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final item = _messages[index];
                final fromUser = item.role == AgentMessageRole.user;
                final markdownStyle =
                    MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF0F172A),
                      ),
                );
                final hasDebugTrace = _showAgentDebugTrace &&
                    !fromUser &&
                    item.debugTrace.trim().isNotEmpty;
                return Align(
                  alignment:
                      fromUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      crossAxisAlignment: fromUser
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Card(
                          color:
                              fromUser ? const Color(0xFFE0F2FF) : Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!fromUser &&
                                    _latestAssistantRuntimeText != null &&
                                    _latestAssistantRuntimeIndex == index) ...[
                                  Text(
                                    _latestAssistantRuntimeText!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: const Color(0xFF94A3B8),
                                          fontSize: 11,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                if (hasDebugTrace) ...[
                                  Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                    ),
                                    child: ExpansionTile(
                                      tilePadding: EdgeInsets.zero,
                                      childrenPadding:
                                          const EdgeInsets.only(bottom: 8),
                                      dense: true,
                                      visualDensity: VisualDensity.compact,
                                      iconColor: const Color(0xFF64748B),
                                      collapsedIconColor:
                                          const Color(0xFF64748B),
                                      title: Text(
                                        '执行轨迹与调试诊断',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: const Color(0xFF64748B),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      children: [
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: const Color(0xFFE2E8F0)),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: IconButton(
                                                  tooltip: '复制轨迹',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  iconSize: 16,
                                                  constraints:
                                                      const BoxConstraints(
                                                    minWidth: 28,
                                                    minHeight: 28,
                                                  ),
                                                  padding: EdgeInsets.zero,
                                                  onPressed: () => _copyText(
                                                    item.debugTrace,
                                                    successHint: '运行轨迹已复制',
                                                  ),
                                                  icon: const Icon(
                                                    Icons.copy_rounded,
                                                    color: Color(0xFF64748B),
                                                  ),
                                                ),
                                              ),
                                              SelectableText(
                                                item.debugTrace,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: const Color(
                                                          0xFF64748B),
                                                      fontSize: 11,
                                                      height: 1.45,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                MarkdownBody(
                                  data: item.content,
                                  selectable: true,
                                  styleSheet: markdownStyle,
                                ),
                                if (item.items.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  ...item.items.map((anime) {
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      minLeadingWidth: 0,
                                      horizontalTitleGap: 10,
                                      leading: SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: anime.coverUrl.trim().isEmpty
                                              ? Container(
                                                  color:
                                                      const Color(0xFFE8EDF6))
                                              : Image.network(
                                                  anime.coverUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      Container(
                                                    color:
                                                        const Color(0xFFE8EDF6),
                                                  ),
                                                  loadingBuilder: (context,
                                                      child, progress) {
                                                    if (progress == null) {
                                                      return child;
                                                    }
                                                    return Container(
                                                        color: const Color(
                                                            0xFFE8EDF6));
                                                  },
                                                ),
                                        ),
                                      ),
                                      title: Text(
                                        anime.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                          '评分 ${anime.ratingScore.toStringAsFixed(1)}'),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => AnimeDetailPage(
                                              subjectId: anime.id,
                                              initialCalendarItem: anime,
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  }),
                                ],
                                if (!fromUser && item.options.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: item.options.map((option) {
                                      return OutlinedButton(
                                        onPressed: _sending
                                            ? null
                                            : () => _handleOptionTap(option),
                                        style: OutlinedButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                        ),
                                        child: Text(
                                          option.requiresManualInput
                                              ? '其他（自行输入）'
                                              : option.label,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(
                            left: fromUser ? 0 : 6,
                            right: fromUser ? 6 : 0,
                            top: 0,
                          ),
                          child: IconButton(
                            tooltip: '复制对话',
                            visualDensity: VisualDensity.compact,
                            iconSize: 16,
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
                            onPressed: () => _copyText(
                              _buildMessageCopyText(item),
                              successHint: '对话内容已复制',
                            ),
                            icon: const Icon(Icons.copy_rounded,
                                color: Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      focusNode: _inputFocusNode,
                      enabled: canSend,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: '告诉星奈你想做什么，例如：把柯南标记为已看完',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: canSend ? _send : null,
                    child: Text(_sending ? '发送中' : '发送'),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '上下文 ${_formatBytes(currentContextBytes)} / 1MB'
                '${_isCurrentSessionContextFull() ? '（已满，请新建对话）' : ''}\n'
                '偏好推荐会综合评分、状态、进度、短评和最近追番记录。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                      fontSize: 11,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
