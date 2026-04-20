import 'dart:async';

import 'package:drama_tracker/screens/auth/register_page.dart';
import 'package:drama_tracker/services/auth_service.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onLoginSuccess,
  });

  final VoidCallback onLoginSuccess;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const String _titleFullText = '欢迎回来，指挥官...';
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String _typedTitle = '';
  Timer? _typeTimer;

  @override
  void initState() {
    super.initState();
    _startTypewriterLoop();
  }

  void _startTypewriterLoop() {
    _typeTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _typedTitle = '';
    });
    var index = 0;
    _typeTimer = Timer.periodic(const Duration(milliseconds: 95), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (index >= _titleFullText.length) {
        timer.cancel();
        _typeTimer = Timer(const Duration(seconds: 5), () {
          if (!mounted) {
            return;
          }
          _startTypewriterLoop();
        });
        return;
      }
      setState(() {
        index += 1;
        _typedTitle = _titleFullText.substring(0, index);
      });
    });
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _userIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
    });
    final error = await AuthService.instance.login(
      userId: _userIdController.text,
      password: _passwordController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
    });
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    widget.onLoginSuccess();
  }

  Future<void> _openRegister() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const RegisterPage(),
      ),
    );
    if (ok == true && mounted) {
      widget.onLoginSuccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFDEE7FF),
                  Color(0xFFF5F7FA),
                ],
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/icons/login.png',
                      width: 210,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _typedTitle,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '登录后轻松管理你的追番进度',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                controller: _userIdController,
                                decoration: const InputDecoration(labelText: '用户ID'),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  labelText: '密码',
                                  suffixIcon: IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              FilledButton(
                                onPressed: _loading ? null : _login,
                                child: Text(_loading ? '登录中...' : '登录'),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _loading ? null : _openRegister,
                                child: const Text('没有账号？去注册'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
