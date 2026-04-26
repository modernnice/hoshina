import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/models/anime_progress.dart';
import 'package:drama_tracker/services/agent/agent_models.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/services/local_notification_service.dart';
import 'package:drama_tracker/services/watch_status_reminder_policy.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';

class AnimeControlTool extends AgentTool {
  AnimeControlTool(this._storage, this._apiService);

  final WatchlistStorage _storage;
  final BangumiApiService _apiService;

  @override
  String get name => 'AnimeControlTool';

  @override
  String get description => '根据自然语言意图增删改追番列表、更新进度和提醒开关。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'intent': {
            'type': 'string',
            'enum': [
              'MARK_WATCHED',
              'MARK_WATCHING',
              'MARK_WANT_TO_WATCH',
              'DELETE_ANIME',
              'UPDATE_PROGRESS',
              'TOGGLE_REMIND',
            ],
          },
          'animeName': {'type': 'string'},
          'animeId': {'type': 'integer'},
          'progress': {'type': 'integer'},
          'remindOn': {'type': 'boolean'},
        },
        'required': ['intent'],
      };

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> input) async {
    final intent = input['intent']?.toString().trim() ?? '';
    final animeId = int.tryParse(input['animeId']?.toString() ?? '');
    final animeName = input['animeName']?.toString().trim() ?? '';
    final progressArg = int.tryParse(input['progress']?.toString() ?? '');
    final remindOn = input['remindOn'];
    final resolution = await _resolveTarget(
      intent: intent,
      animeId: animeId,
      animeName: animeName,
    );
    if (resolution.requiresClarification) {
      return AgentToolResult(
        success: false,
        message: '找到多个候选，必须先确认具体要操作哪一部',
        items: resolution.candidates,
        payload: {
          'requiresClarification': true,
          'toolName': name,
          'intent': intent,
          'animeName': animeName,
        },
      );
    }
    switch (intent) {
      case 'DELETE_ANIME':
        final target = resolution.localTarget;
        if (target == null) {
          return const AgentToolResult(success: false, message: '未找到该番剧，无法删除');
        }
        await LocalNotificationService.instance.cancelReminder(target.subjectId);
        await _storage.delete(target.subjectId);
        return AgentToolResult(success: true, message: '已删除《${target.name}》');
      case 'MARK_WATCHED':
      case 'MARK_WATCHING':
      case 'MARK_WANT_TO_WATCH':
        final status = intent == 'MARK_WATCHED'
            ? WatchStatus.finished
            : intent == 'MARK_WATCHING'
                ? WatchStatus.watching
                : WatchStatus.wish;
        final target = resolution.localTarget;
        if (target == null && resolution.remoteTarget == null) {
          return const AgentToolResult(success: false, message: '未找到该番剧，无法修改状态');
        }
        final base = target ?? _buildProgressFromRemote(resolution.remoteTarget!, status: status);
        final next = WatchStatusReminderPolicy.normalize(
          base.copyWith(status: status, statusSelected: true),
        );
        if (base.reminderEnabled && !next.reminderEnabled) {
          await LocalNotificationService.instance.cancelReminder(next.subjectId);
        }
        await _storage.upsert(next);
        return AgentToolResult(success: true, message: '已将《${next.name}》标记为${_statusText(status)}');
      case 'UPDATE_PROGRESS':
        final target = resolution.localTarget;
        if (target == null) {
          return const AgentToolResult(success: false, message: '未找到该番剧，无法更新进度');
        }
        if (progressArg == null) {
          return const AgentToolResult(success: false, message: '请提供有效的进度数字');
        }
        var nextProgress = progressArg;
        if (nextProgress < 0) {
          nextProgress = 0;
        }
        if (target.totalEpisodes > 0 && nextProgress > target.totalEpisodes) {
          nextProgress = target.totalEpisodes;
        }
        await _storage.upsert(target.copyWith(currentEpisode: nextProgress));
        return AgentToolResult(success: true, message: '《${target.name}》进度已更新为 $nextProgress 集');
      case 'TOGGLE_REMIND':
        final target = resolution.localTarget;
        if (target == null) {
          return const AgentToolResult(success: false, message: '未找到该番剧，无法修改提醒');
        }
        final on = remindOn?.toString() == 'true';
        if (on &&
            !WatchStatusReminderPolicy.canEnableReminderForSelectedStatusName(
              target.statusSelected ? target.status.name : null,
            )) {
          return const AgentToolResult(success: false, message: '只有标记为在看时才能开启提醒');
        }
        final next = target.copyWith(reminderEnabled: on);
        await _storage.upsert(next);
        if (on) {
          await LocalNotificationService.instance.scheduleWeeklyReminder(
            subjectId: next.subjectId,
            animeName: next.name,
            airWeekday: next.updateWeekday,
            hour: next.reminderHour,
            minute: next.reminderMinute,
          );
        } else {
          await LocalNotificationService.instance.cancelReminder(next.subjectId);
        }
        return AgentToolResult(success: true, message: '《${target.name}》提醒已${on ? '开启' : '关闭'}');
      default:
        return AgentToolResult(success: false, message: '暂不支持的操作：$intent');
    }
  }

  Future<_ControlResolution> _resolveTarget({
    required String intent,
    required int? animeId,
    required String animeName,
  }) async {
    final local = _resolveLocal(animeId, animeName);
    if (local.requiresClarification || local.localTarget != null) {
      return local;
    }
    if (!_allowsRemoteResolution(intent)) {
      return local;
    }
    if (animeId != null && animeId > 0) {
      final byId = await _resolveBySubjectId(animeId);
      if (byId.localTarget != null || byId.remoteTarget != null) {
        return byId;
      }
    }
    if (animeName.trim().isEmpty) {
      return local;
    }
    return _resolveBySearch(animeId: animeId, animeName: animeName);
  }

  _ControlResolution _resolveLocal(int? animeId, String animeName) {
    final all = _storage.getAllProgresses();
    if (animeId != null && animeId > 0) {
      for (final item in all) {
        if (item.subjectId == animeId) {
          return _ControlResolution(localTarget: item);
        }
      }
    }
    final key = _normalize(animeName);
    if (key.isEmpty) {
      return const _ControlResolution();
    }
    final exact = <AnimeProgress>[];
    final fuzzy = <AnimeProgress>[];
    for (final item in all) {
      final normalized = _normalize(item.name);
      if (normalized == key) {
        exact.add(item);
      } else if (normalized.contains(key) || key.contains(normalized)) {
        fuzzy.add(item);
      }
    }
    if (exact.length == 1) {
      return _ControlResolution(localTarget: exact.first);
    }
    final candidates = exact.isNotEmpty ? exact : fuzzy;
    if (candidates.length > 1) {
      return _ControlResolution(
        requiresClarification: true,
        candidates: candidates.map(_progressToItem).toList(),
      );
    }
    if (candidates.length == 1) {
      return _ControlResolution(localTarget: candidates.first);
    }
    return const _ControlResolution();
  }

  Future<_ControlResolution> _resolveBySearch({
    required int? animeId,
    required String animeName,
  }) async {
    try {
      final page = await _apiService.searchSubjects(keyword: animeName, limit: 5, offset: 0);
      if (page.data.isEmpty) {
        return const _ControlResolution();
      }
      if (animeId != null && animeId > 0) {
        for (final item in page.data) {
          if (item.id == animeId) {
            final existing = _storage.getProgress(item.id);
            if (existing != null) {
              return _ControlResolution(localTarget: existing);
            }
            return _ControlResolution(remoteTarget: item);
          }
        }
      }
      final key = _normalize(animeName);
      final isFirstSeasonSearch = key.endsWith('第一季') || key.endsWith('第1季');
      final fallbackKey = isFirstSeasonSearch ? key.replaceAll(RegExp(r'第一季$|第1季$'), '') : '';

      final exact = page.data.where((item) {
        final normalized = _normalize(item.name);
        return normalized == key || (fallbackKey.isNotEmpty && normalized == fallbackKey);
      }).toList();
      
      if (exact.length == 1) {
        final existing = _storage.getProgress(exact.first.id);
        if (existing != null) {
          return _ControlResolution(localTarget: existing);
        }
        return _ControlResolution(remoteTarget: exact.first);
      }
      final fuzzy = page.data.where((item) {
        final normalized = _normalize(item.name);
        return normalized.contains(key) || key.contains(normalized) || 
               (fallbackKey.isNotEmpty && (normalized.contains(fallbackKey) || fallbackKey.contains(normalized)));
      }).toList();
      final candidates = exact.isNotEmpty ? exact : fuzzy;
      if (candidates.length == 1) {
        final existing = _storage.getProgress(candidates.first.id);
        if (existing != null) {
          return _ControlResolution(localTarget: existing);
        }
        return _ControlResolution(remoteTarget: candidates.first);
      }
      return _ControlResolution(
        requiresClarification: true,
        candidates: (candidates.isNotEmpty ? candidates : page.data).take(10).toList(),
      );
    } catch (_) {
      return const _ControlResolution();
    }
  }

  Future<_ControlResolution> _resolveBySubjectId(int animeId) async {
    try {
      final existing = _storage.getProgress(animeId);
      if (existing != null) {
        return _ControlResolution(localTarget: existing);
      }
      final detail = await _apiService.fetchSubjectDetail(animeId);
      if (detail.id <= 0) {
        return const _ControlResolution();
      }
      return _ControlResolution(
        remoteTarget: AnimeCalendarItem(
          id: detail.id,
          name: detail.name,
          coverUrl: detail.coverUrl,
          airWeekday: detail.airWeekday,
          airDate: detail.airDate,
          ratingScore: detail.ratingScore,
          doingCount: detail.collectionDoing,
          totalEpisodes: detail.totalEpisodes,
          summary: detail.summary,
        ),
      );
    } catch (_) {
      return const _ControlResolution();
    }
  }

  bool _allowsRemoteResolution(String intent) {
    return intent == 'MARK_WATCHED' ||
        intent == 'MARK_WATCHING' ||
        intent == 'MARK_WANT_TO_WATCH';
  }

  AnimeProgress _buildProgressFromRemote(
    AnimeCalendarItem item, {
    required WatchStatus status,
  }) {
    return AnimeProgress(
      subjectId: item.id,
      name: item.name,
      coverUrl: item.coverUrl,
      currentEpisode: 0,
      totalEpisodes: item.totalEpisodes,
      status: status,
      statusSelected: true,
      updateWeekday: item.airWeekday,
      privateRating: 0,
      privateReview: '',
      reminderEnabled: false,
      reminderHour: 20,
      reminderMinute: 0,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  AnimeCalendarItem _progressToItem(AnimeProgress progress) {
    return AnimeCalendarItem(
      id: progress.subjectId,
      name: progress.name,
      coverUrl: progress.coverUrl,
      airWeekday: progress.updateWeekday,
      airDate: '',
      ratingScore: 0,
      doingCount: 0,
      totalEpisodes: progress.totalEpisodes,
      summary: '',
    );
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp("[\\s·:：\\-—_!！?？,，.。/／\\(\\)（）\\[\\]【】「」『』\"“”'《》]"), '')
        .trim();
  }

  String _statusText(WatchStatus status) {
    switch (status) {
      case WatchStatus.wish:
        return '想看';
      case WatchStatus.watching:
        return '在看';
      case WatchStatus.finished:
        return '已看完';
    }
  }
}

class _ControlResolution {
  const _ControlResolution({
    this.localTarget,
    this.remoteTarget,
    this.candidates = const [],
    this.requiresClarification = false,
  });

  final AnimeProgress? localTarget;
  final AnimeCalendarItem? remoteTarget;
  final List<AnimeCalendarItem> candidates;
  final bool requiresClarification;
}
