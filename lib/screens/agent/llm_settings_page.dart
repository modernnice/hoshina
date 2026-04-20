import 'package:drama_tracker/models/llm_config.dart';
import 'package:drama_tracker/models/llm_provider_preset.dart';
import 'package:drama_tracker/services/llm_config_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LlmSettingsPage extends StatefulWidget {
  const LlmSettingsPage({super.key});

  @override
  State<LlmSettingsPage> createState() => _LlmSettingsPageState();
}

class _LlmSettingsPageState extends State<LlmSettingsPage> {
  static const String _customModelOption = '__custom_model__';

  final _storage = LlmConfigStorage();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  final _keyFocusNode = FocusNode();
  final _displayLimitController = TextEditingController(text: '10');
  final _maxToolRoundsController = TextEditingController(text: '10');
  LlmProviderPreset _selectedPreset = LlmProviderPreset.custom;
  bool _useCustomModelName = false;
  bool _obscureApiKey = true;
  bool _enableAgentDebugTrace = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _keyFocusNode.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    final config = _storage.getConfig();
    if (config != null) {
      _nameController.text = config.llmName;
      _urlController.text = config.llmUrl;
      _keyController.text = config.llmKey;
      _displayLimitController.text = config.normalizedMessageDisplayLimit.toString();
      _maxToolRoundsController.text = config.normalizedMaxToolRounds.toString();
      _enableAgentDebugTrace = config.enableAgentDebugTrace;
      _selectedPreset = LlmProviderPreset.inferFrom(
        url: config.llmUrl,
        model: config.llmName,
      );
      _useCustomModelName = _selectedPreset.models.isNotEmpty &&
          !_selectedPreset.models.contains(config.llmName.trim()) &&
          config.llmName.trim().isNotEmpty;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    _keyFocusNode.dispose();
    _displayLimitController.dispose();
    _maxToolRoundsController.dispose();
    super.dispose();
  }

  void _applyPreset(LlmProviderPreset preset) {
    setState(() {
      _selectedPreset = preset;
      if (preset == LlmProviderPreset.custom) {
        _urlController.clear();
        _nameController.clear();
        _useCustomModelName = true;
        return;
      }
      _urlController.text = preset.baseUrl;
      _useCustomModelName = false;
      if (_nameController.text.trim().isEmpty ||
          !preset.models.contains(_nameController.text.trim())) {
        _nameController.text = preset.defaultModel;
      }
    });
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开链接：$url')),
      );
    }
  }

  Widget _buildFooter(BuildContext context) {
    final linkStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF58B6F0),
    );
    final separatorStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: 13,
      color: Theme.of(context).colorScheme.outline,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < LlmProviderPreset.presets.length; i++) ...[
                GestureDetector(
                  onTap: () => _openLink(LlmProviderPreset.presets[i].apiKeyUrl),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(LlmProviderPreset.presets[i].label, style: linkStyle),
                  ),
                ),
                if (i != LlmProviderPreset.presets.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text('｜', style: separatorStyle),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '星奈目前已支持直接切换多个国产大模型，点击上面模型名称获取API key',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    String? helper,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      suffixIcon: suffixIcon,
      hintStyle: const TextStyle(
        fontSize: 13,
        color: Color(0xFF94A3B8),
      ),
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF1F5FB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD6DFEE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD6DFEE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF00BFFF), width: 1.6),
      ),
    );
  }

  TextStyle _dropdownTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF334155),
    );
  }

  String? _selectedModelValue() {
    if (_selectedPreset.models.isEmpty || _useCustomModelName) {
      return _customModelOption;
    }
    final current = _nameController.text.trim();
    if (current.isEmpty) {
      return _selectedPreset.defaultModel;
    }
    if (_selectedPreset.models.contains(current)) {
      return current;
    }
    if (_selectedPreset.models.isNotEmpty) {
      return null;
    }
    return null;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    final key = _keyController.text.trim();
    final displayLimit = int.tryParse(_displayLimitController.text.trim()) ?? 10;
    final maxToolRounds = int.tryParse(_maxToolRoundsController.text.trim()) ?? 10;
    if (name.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请完善模型名称和 URL')),
      );
      return;
    }
    final parsed = Uri.tryParse(url);
    final validUrl = parsed != null && (parsed.isScheme('http') || parsed.isScheme('https'));
    if (!validUrl) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL 格式不正确，请检查')),
      );
      return;
    }
    if (displayLimit < 1 || displayLimit > 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('展示上限请填写 1-20 的整数')),
      );
      return;
    }
    if (maxToolRounds < 1 || maxToolRounds > 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('工具调用轮数请填写 1-15 的整数，避免循环过长')),
      );
      return;
    }
    setState(() {
      _saving = true;
    });
    await _storage.saveConfig(
      LlmConfig(
        llmName: name,
        llmUrl: url,
        llmKey: key,
        isEncrypted: false,
        messageDisplayLimit: displayLimit,
        maxToolRounds: maxToolRounds,
        enableAgentDebugTrace: _enableAgentDebugTrace,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('模型配置已保存（仅本地）')),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模型配置')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _selectedPreset.id,
                        decoration: _fieldDecoration(label: '模型供应商'),
                        style: _dropdownTextStyle(context),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        menuMaxHeight: 320,
                        isDense: true,
                        items: [
                          for (final preset in [
                            ...LlmProviderPreset.presets,
                            LlmProviderPreset.custom,
                          ])
                            DropdownMenuItem<String>(
                              value: preset.id,
                              child: Text(
                                preset.label,
                                style: _dropdownTextStyle(context),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          final preset = [
                            ...LlmProviderPreset.presets,
                            LlmProviderPreset.custom,
                          ].firstWhere((item) => item.id == value);
                          _applyPreset(preset);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _urlController,
                        readOnly: _selectedPreset != LlmProviderPreset.custom,
                        style: TextStyle(
                          color: _selectedPreset == LlmProviderPreset.custom
                              ? const Color(0xFF111827)
                              : const Color(0xFF94A3B8),
                        ),
                        decoration: _fieldDecoration(
                          label: '模型 API URL',
                          hint: '如 https://api.deepseek.com/v1',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_selectedPreset.models.isNotEmpty && !_useCustomModelName)
                        DropdownButtonFormField<String>(
                          initialValue: _selectedModelValue(),
                          decoration: _fieldDecoration(label: '模型名称'),
                          style: _dropdownTextStyle(context),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                          dropdownColor: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          menuMaxHeight: 320,
                          isDense: true,
                          items: [
                            for (final model in _selectedPreset.models)
                              DropdownMenuItem<String>(
                                value: model,
                                child: Text(
                                  model,
                                  style: _dropdownTextStyle(context),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            DropdownMenuItem<String>(
                              value: _customModelOption,
                              child: Text(
                                '自定义模型名称',
                                style: _dropdownTextStyle(context),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            if (value == _customModelOption) {
                              _nameController.clear();
                              setState(() {
                                _useCustomModelName = true;
                              });
                              return;
                            }
                            _nameController.text = value;
                            setState(() {
                              _useCustomModelName = false;
                            });
                          },
                        )
                      else
                        TextField(
                          controller: _nameController,
                          decoration: _fieldDecoration(
                            label: '模型名称',
                            hint: _selectedPreset.models.isNotEmpty
                                ? '请输入自定义模型名称'
                                : '如 deepseek-chat / kimi-k2.5 / qwen-plus',
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _keyController,
                        focusNode: _keyFocusNode,
                        decoration: _fieldDecoration(
                          label: '模型密钥（可选）',
                          hint: _keyFocusNode.hasFocus && _keyController.text.trim().isEmpty
                              ? '点击最下方模型名称获取密钥'
                              : null,
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscureApiKey = !_obscureApiKey;
                              });
                            },
                            icon: Icon(
                              _obscureApiKey
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                          ),
                        ),
                        obscureText: _obscureApiKey,
                        onChanged: (_) {
                          if (mounted) {
                            setState(() {});
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _displayLimitController,
                        keyboardType: TextInputType.number,
                        decoration: _fieldDecoration(
                          label: '聊天卡片展示最大上限',
                          hint: '默认 10，范围 1-20（最终数量由 Agent 决定）',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _maxToolRoundsController,
                        keyboardType: TextInputType.number,
                        decoration: _fieldDecoration(
                          label: '工具最多调用轮数',
                          hint: '默认 10，建议 3-10，最大 15（过大可能循环）',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        value: _enableAgentDebugTrace,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('开启 ReAct 推理工具链展示'),
                        subtitle: const Text(
                          '展示模型轮次输出、工具参数和结果摘要。',
                        ),
                        onChanged: (value) {
                          setState(() {
                            _enableAgentDebugTrace = value;
                          });
                        },
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? '保存中...' : '保存配置'),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '提示：配置仅保存在本机，不会上传到云端。',
                        textAlign: TextAlign.center,
                      ),
                      const Spacer(),
                      _buildFooter(context),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
