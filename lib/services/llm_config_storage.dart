import 'package:drama_tracker/models/llm_config.dart';
import 'package:hive/hive.dart';

class LlmConfigStorage {
  LlmConfigStorage() : _box = Hive.box<Map>('llm_config_box');

  static const String _defaultKey = 'default';
  final Box<Map> _box;

  LlmConfig? getConfig() {
    final map = _box.get(_defaultKey);
    if (map == null) {
      return null;
    }
    return LlmConfig.fromMap(Map<String, dynamic>.from(map));
  }

  int getMessageDisplayLimit() {
    final config = getConfig();
    if (config == null) {
      return 10;
    }
    return config.normalizedMessageDisplayLimit;
  }

  Future<void> saveConfig(LlmConfig config) async {
    await _box.put(_defaultKey, config.toMap());
  }

  Future<void> clearConfig() async {
    await _box.delete(_defaultKey);
  }
}
