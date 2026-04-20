import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  SupabaseClient? get _clientOrNull {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Session? get currentSession => _clientOrNull?.auth.currentSession;

  String _emailFromUserId(String userId) {
    final raw = userId.trim().toLowerCase();
    final normalized = raw.replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
    final localPart = normalized.isEmpty ? 'u' : normalized;
    return '$localPart@dramatracker.app';
  }

  Future<String?> register({
    required String userId,
    required String nickname,
    required String password,
  }) async {
    final client = _clientOrNull;
    if (client == null) {
      return '服务暂不可用，请稍后重试';
    }
    final normalizedUserId = userId.trim();
    final normalizedNickname = nickname.trim();
    if (normalizedUserId.isEmpty || normalizedNickname.isEmpty || password.trim().isEmpty) {
      return '请完整填写注册信息';
    }
    try {
      final email = _emailFromUserId(normalizedUserId);
      final authRes = await client.auth.signUp(
        email: email,
        password: password,
      );
      final user = authRes.user;
      final session = authRes.session ?? client.auth.currentSession;
      if (user == null || session == null) {
        return '注册成功，但未获取登录会话，请检查邮箱验证设置';
      }
      await client.from('profiles').insert({
        'id': user.id,
        'user_id': normalizedUserId,
        'nickname': normalizedNickname,
      });
      return null;
    } on AuthException catch (e) {
      if ((e.message).toLowerCase().contains('already')) {
        return '该用户ID已存在，请重新选择';
      }
      return e.message;
    } on PostgrestException catch (e) {
      if ((e.message).toLowerCase().contains('duplicate')) {
        return '该用户ID已存在，请重新选择';
      }
      return e.message;
    } catch (_) {
      return '注册失败，请稍后重试';
    }
  }

  Future<String?> login({
    required String userId,
    required String password,
  }) async {
    final client = _clientOrNull;
    if (client == null) {
      return '服务暂不可用，请稍后重试';
    }
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty || password.trim().isEmpty) {
      return '请输入用户ID和密码';
    }
    try {
      await client.auth.signInWithPassword(
        email: _emailFromUserId(normalizedUserId),
        password: password,
      );
      return null;
    } on AuthException {
      return '账号或密码错误';
    } catch (_) {
      return '登录失败，请稍后重试';
    }
  }

  Future<String?> updatePassword(String newPassword) async {
    final client = _clientOrNull;
    if (client == null) {
      return '服务暂不可用，请稍后重试';
    }
    if (newPassword.trim().isEmpty) {
      return '密码不能为空';
    }
    try {
      await client.auth.updateUser(UserAttributes(password: newPassword));
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return '修改密码失败，请稍后重试';
    }
  }

  Future<void> logout() async {
    final client = _clientOrNull;
    if (client == null) {
      return;
    }
    
    // Clear local user-specific data to prevent data leaks between accounts
    try {
      if (Hive.isBoxOpen('watchlist')) {
        await Hive.box<Map>('watchlist').clear();
      }
      if (Hive.isBoxOpen('agent_chat_sessions')) {
        await Hive.box<Map>('agent_chat_sessions').clear();
      }
      // Note: We intentionally do NOT clear 'llm_config_box' as API keys and settings 
      // are usually device-level preferences rather than account-bound.
    } catch (e) {
      debugPrint('Error clearing local data on logout: $e');
    }

    await client.auth.signOut();
  }
}
