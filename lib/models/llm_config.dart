class LlmConfig {
  const LlmConfig({
    required this.llmName,
    required this.llmUrl,
    required this.llmKey,
    required this.isEncrypted,
    this.messageDisplayLimit = 10,
    this.maxToolRounds = 10,
    this.enableAgentDebugTrace = false,
  });

  final String llmName;
  final String llmUrl;
  final String llmKey;
  final bool isEncrypted;
  final int messageDisplayLimit;
  final int maxToolRounds;
  final bool enableAgentDebugTrace;

  bool get isValid => llmName.trim().isNotEmpty && llmUrl.trim().isNotEmpty;

  int get normalizedMessageDisplayLimit {
    return messageDisplayLimit.clamp(1, 20);
  }

  int get normalizedMaxToolRounds {
    return maxToolRounds.clamp(1, 15);
  }

  Map<String, dynamic> toMap() {
    return {
      'llmName': llmName,
      'llmUrl': llmUrl,
      'llmKey': llmKey,
      'isEncrypted': isEncrypted,
      'messageDisplayLimit': normalizedMessageDisplayLimit,
      'maxToolRounds': normalizedMaxToolRounds,
      'enableAgentDebugTrace': enableAgentDebugTrace,
    };
  }

  factory LlmConfig.fromMap(Map<String, dynamic> map) {
    return LlmConfig(
      llmName: map['llmName']?.toString() ?? '',
      llmUrl: map['llmUrl']?.toString() ?? '',
      llmKey: map['llmKey']?.toString() ?? '',
      isEncrypted: map['isEncrypted']?.toString() == 'true',
      messageDisplayLimit: int.tryParse((map['messageDisplayLimit'] ?? 10).toString()) ?? 10,
      maxToolRounds: int.tryParse((map['maxToolRounds'] ?? 10).toString()) ?? 10,
      enableAgentDebugTrace: (map['enableAgentDebugTrace'] ?? false).toString() == 'true',
    );
  }

  LlmConfig copyWith({
    String? llmName,
    String? llmUrl,
    String? llmKey,
    bool? isEncrypted,
    int? messageDisplayLimit,
    int? maxToolRounds,
    bool? enableAgentDebugTrace,
  }) {
    return LlmConfig(
      llmName: llmName ?? this.llmName,
      llmUrl: llmUrl ?? this.llmUrl,
      llmKey: llmKey ?? this.llmKey,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      messageDisplayLimit: messageDisplayLimit ?? this.messageDisplayLimit,
      maxToolRounds: maxToolRounds ?? this.maxToolRounds,
      enableAgentDebugTrace: enableAgentDebugTrace ?? this.enableAgentDebugTrace,
    );
  }
}
