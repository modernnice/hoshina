import 'package:drama_tracker/config/supabase_config.dart';
import 'package:drama_tracker/screens/app_shell_page.dart';
import 'package:drama_tracker/screens/anime_detail_page.dart';
import 'package:drama_tracker/screens/auth/login_page.dart';
import 'package:drama_tracker/services/auth_service.dart';
import 'package:drama_tracker/services/cloud_sync_service.dart';
import 'package:drama_tracker/services/local_notification_service.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';
import 'package:drama_tracker/widgets/global_agent_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('加载 .env 失败，将继续尝试使用现有配置: $e');
  }
  await Hive.initFlutter();
  await Hive.openBox<Map>('watchlist');
  await Hive.openBox<Map>('llm_config_box');
  await Hive.openBox<Map>('agent_chat_sessions');
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  }
  try {
    await LocalNotificationService.instance.initialize();
  } catch (e) {
    debugPrint('初始化本地通知失败: $e');
  }
  runApp(const DramaTrackerApp());
}

class DramaTrackerApp extends StatefulWidget {
  const DramaTrackerApp({super.key});

  @override
  State<DramaTrackerApp> createState() => _DramaTrackerAppState();
}

class _DramaTrackerAppState extends State<DramaTrackerApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final WatchlistStorage _storage = WatchlistStorage();
  bool _notificationNavigationScheduled = false;
  int? _notificationNavigationInFlightSubjectId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocalNotificationService.instance.setTapHandler((subjectId) {
      _scheduleNotificationNavigation();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleNotificationNavigation();
      _restoreLocalNotifications();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleNotificationNavigation();
    }
  }

  bool get _isLoggedIn {
    if (!SupabaseConfig.isConfigured) {
      return false;
    }
    return AuthService.instance.currentSession != null;
  }

  bool _tryOpenSubjectDetailFromNotification(int subjectId) {
    if (!_isLoggedIn) {
      debugPrint('通知跳转暂缓，当前未登录，subjectId=$subjectId');
      return false;
    }
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      debugPrint('通知跳转暂缓，navigator 未就绪，subjectId=$subjectId');
      return false;
    }
    if (_notificationNavigationInFlightSubjectId == subjectId) {
      debugPrint('通知跳转已在进行中，subjectId=$subjectId');
      return false;
    }
    _notificationNavigationInFlightSubjectId = subjectId;
    try {
      debugPrint('准备跳转到番剧详情，subjectId=$subjectId');
      navigator
          .push(
            MaterialPageRoute(
              builder: (_) => AnimeDetailPage(subjectId: subjectId),
            ),
          )
          .whenComplete(() {
            if (!mounted) {
              return;
            }
            if (_notificationNavigationInFlightSubjectId == subjectId) {
              _notificationNavigationInFlightSubjectId = null;
            }
          });
      LocalNotificationService.instance.clearPendingSubjectId(subjectId);
    } catch (e) {
      _notificationNavigationInFlightSubjectId = null;
      debugPrint('通知跳转到番剧详情失败: $e');
      return false;
    }
    return true;
  }

  void _scheduleNotificationNavigation() {
    if (_notificationNavigationScheduled) {
      return;
    }
    _notificationNavigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationNavigationScheduled = false;
      _tryOpenPendingNotificationSubject();
    });
  }

  void _tryOpenPendingNotificationSubject() {
    final pending = LocalNotificationService.instance.peekPendingSubjectId();
    if (pending == null) {
      return;
    }
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.detached ||
        lifecycleState == AppLifecycleState.hidden) {
      debugPrint('通知跳转暂缓，应用生命周期=$lifecycleState，subjectId=$pending');
      return;
    }
    _tryOpenSubjectDetailFromNotification(pending);
  }

  void _refreshAuthState() {
    if (!mounted) {
      return;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleNotificationNavigation();
    });
    
    if (_isLoggedIn) {
      CloudSyncService.instance.downloadToLocalPreferences(_storage).then((_) async {
        await _restoreLocalNotifications();
        if (mounted) {
          setState(() {});
        }
        _scheduleNotificationNavigation();
      });
    }
  }

  Future<void> _restoreLocalNotifications() async {
    try {
      await LocalNotificationService.instance.syncAllFromStorage(_storage);
    } catch (e) {
      debugPrint('恢复本地通知失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeWidget = !SupabaseConfig.isConfigured
        ? const _SupabaseConfigMissingPage()
        : (_isLoggedIn
            ? AppShellPage(onLogout: _refreshAuthState)
            : LoginPage(onLoginSuccess: _refreshAuthState));
    return MaterialApp(
      title: '番剧追更',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF00BFFF),
          onPrimary: Colors.white,
          secondary: Color(0xFF4FD1C5),
          onSecondary: Color(0xFF062925),
          error: Color(0xFFDC2626),
          onError: Colors.white,
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF0F172A),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
            letterSpacing: 0.15,
            height: 1.18,
          ),
          titleMedium: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
            letterSpacing: 0.1,
            height: 1.2,
          ),
          bodyLarge: TextStyle(
            fontSize: 15,
            color: Color(0xFF1E293B),
            height: 1.45,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            color: Color(0xFF475569),
            height: 1.4,
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFF5F7FA),
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
            letterSpacing: 0.2,
            height: 1.15,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0.8,
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE6EBF5)),
          ),
          color: Colors.white,
          shadowColor: const Color(0x140F172A),
          surfaceTintColor: Colors.transparent,
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: const BorderSide(color: Color(0xFFDDE5F3)),
          backgroundColor: const Color(0xFFF8FAFF),
          selectedColor: const Color(0xFFE4EBFF),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF1F5FB),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
          hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
          labelStyle: const TextStyle(color: Color(0xFF64748B)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            backgroundColor: const Color(0xFF00BFFF),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 42),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            side: const BorderSide(color: Color(0xFFD6DEEE)),
            foregroundColor: const Color(0xFF334155),
          ),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFFE8EDF6)),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Color(0xFFE4EBFF),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      builder: (context, child) {
        final body = child ?? const SizedBox.shrink();
        if (!_isLoggedIn) {
          return body;
        }
        return Stack(
          children: [
            body,
            GlobalAgentFab(navigatorKey: _navigatorKey),
          ],
        );
      },
      home: homeWidget,
    );
  }
}

class _SupabaseConfigMissingPage extends StatelessWidget {
  const _SupabaseConfigMissingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '请先在 lib/config/supabase_config.dart 填写 Supabase URL 和 anon key，完成后重启应用。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
