class LlmProviderPreset {
  const LlmProviderPreset({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.models,
    required this.apiKeyUrl,
  });

  final String id;
  final String label;
  final String baseUrl;
  final List<String> models;
  final String apiKeyUrl;

  String get defaultModel => models.first;

  static const custom = LlmProviderPreset(
    id: 'custom',
    label: '自定义',
    baseUrl: '',
    models: <String>[],
    apiKeyUrl: '',
  );

  static const presets = <LlmProviderPreset>[
    LlmProviderPreset(
      id: 'deepseek',
      label: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      models: <String>['deepseek-chat', 'deepseek-reasoner'],
      apiKeyUrl: 'https://platform.deepseek.com/console/api-keys',
    ),
    LlmProviderPreset(
      id: 'minimax',
      label: 'MiniMax',
      baseUrl: 'https://api.minimax.com/v1',
      models: <String>[
        'MiniMax-M2.7',
        'MiniMax-M2.7-highspeed',
        'MiniMax-M2.5',
        'MiniMax-M2.5-highspeed',
        'MiniMax-M2.1',
        'MiniMax-M2.1-highspeed',
        'MiniMax-M2',
      ],
      apiKeyUrl: 'https://platform.minimax.com/',
    ),
    LlmProviderPreset(
      id: 'glm',
      label: 'GLM',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      models: <String>[
        'GLM-5.1',
        'GLM-5',
        'GLM-5-Turbo',
        'GLM-4.7',
        'GLM-4.7-FlashX',
      ],
      apiKeyUrl: 'https://open.bigmodel.cn/',
    ),
    LlmProviderPreset(
      id: 'kimi',
      label: 'Kimi',
      baseUrl: 'https://api.moonshot.cn/v1',
      models: <String>[
        'kimi-k2.5',
        'kimi-k2-0905-preview',
        'kimi-k2-0711-preview',
        'kimi-k2-turbo-preview',
        'kimi-k2-thinking',
        'kimi-k2-thinking-turbo',
      ],
      apiKeyUrl: 'https://platform.moonshot.cn/',
    ),
    LlmProviderPreset(
      id: 'qwen',
      label: 'Qwen',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      models: <String>['qwen-max', 'qwen-plus', 'qwen-turbo'],
      apiKeyUrl: 'https://bailian.console.aliyun.com/',
    ),
  ];

  static LlmProviderPreset inferFrom({
    required String url,
    required String model,
  }) {
    final normalizedUrl = url.trim().toLowerCase();
    final normalizedModel = model.trim().toLowerCase();
    for (final preset in presets) {
      if (normalizedUrl.startsWith(preset.baseUrl.toLowerCase())) {
        return preset;
      }
      if (preset.models.any((item) => item.toLowerCase() == normalizedModel)) {
        return preset;
      }
    }
    return custom;
  }
}
