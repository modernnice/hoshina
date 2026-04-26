import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/models/anime_detail.dart';
import 'package:drama_tracker/models/anime_progress.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/services/local_notification_service.dart';
import 'package:drama_tracker/services/watch_status_reminder_policy.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';
import 'package:drama_tracker/utils/network_error_helper.dart';
import 'package:drama_tracker/widgets/no_network_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class AnimeDetailPage extends StatefulWidget {
  const AnimeDetailPage({
    super.key,
    required this.subjectId,
    this.initialCalendarItem,
  });

  final int subjectId;
  final AnimeCalendarItem? initialCalendarItem;

  @override
  State<AnimeDetailPage> createState() => _AnimeDetailPageState();
}

class _AnimeDetailPageState extends State<AnimeDetailPage> {
  static const double _detailHeaderExpandedHeight = 390;
  final BangumiApiService _apiService = BangumiApiService();
  final WatchlistStorage _watchlistStorage = WatchlistStorage();
  final TextEditingController _episodeController = TextEditingController();
  final TextEditingController _privateReviewController = TextEditingController();

  bool _loading = true;
  String? _errorMessage;
  AnimeDetail? _detail;
  List<AnimeCharacter> _characters = [];
  bool _characterLoadFailed = false;
  AnimeProgress? _progress;
  WatchStatus? _selectedStatus;
  bool _isTitlePinnedTop = false;

  static const Map<int, String> _weekdayLabels = {
    1: '周一',
    2: '周二',
    3: '周三',
    4: '周四',
    5: '周五',
    6: '周六',
    7: '周日',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _saveProgress(showTip: false);
    _episodeController.dispose();
    _privateReviewController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _characterLoadFailed = false;
    });
    try {
      final local = _watchlistStorage.getProgress(widget.subjectId);
      final detailFuture = _apiService.fetchSubjectDetail(widget.subjectId);
      final charactersFuture = _apiService.fetchSubjectCharacters(widget.subjectId);
      final detail = await detailFuture;
      var characters = <AnimeCharacter>[];
      var characterLoadFailed = false;
      try {
        characters = await charactersFuture;
        characters.sort(AnimeCharacter.compareByRolePriority);
      } catch (_) {
        characterLoadFailed = true;
      }
      final initial = widget.initialCalendarItem;
      final totalFromDetail = detail.totalEpisodes;
      final resolvedWeekday = detail.airWeekday > 0 ? detail.airWeekday : (initial?.airWeekday ?? 0);
      final resolvedAirDate = detail.airDate.isNotEmpty ? detail.airDate : (initial?.airDate ?? '');
      final merged = (local ??
              AnimeProgress(
                subjectId: detail.id,
                name: detail.name.isNotEmpty ? detail.name : (initial?.name ?? '未知番剧'),
                coverUrl: detail.coverUrl.isNotEmpty ? detail.coverUrl : (initial?.coverUrl ?? ''),
                currentEpisode: 0,
                totalEpisodes: totalFromDetail,
                status: WatchStatus.wish,
                statusSelected: false,
                updateWeekday: resolvedWeekday,
                privateRating: 0,
                privateReview: '',
                reminderEnabled: false,
                reminderHour: LocalNotificationService.defaultReminderHour,
                reminderMinute: LocalNotificationService.defaultReminderMinute,
                createdAtMs: DateTime.now().millisecondsSinceEpoch,
              ))
          .copyWith(
        name: detail.name.isNotEmpty ? detail.name : (initial?.name ?? local?.name ?? '未知番剧'),
        coverUrl: detail.coverUrl.isNotEmpty ? detail.coverUrl : (initial?.coverUrl ?? local?.coverUrl ?? ''),
        totalEpisodes: totalFromDetail > 0 ? totalFromDetail : local?.totalEpisodes ?? 0,
        updateWeekday: resolvedWeekday > 0 ? resolvedWeekday : local?.updateWeekday ?? 0,
      );
      final normalized = merged.totalEpisodes > 0 && merged.currentEpisode > merged.totalEpisodes
          ? merged.copyWith(currentEpisode: merged.totalEpisodes)
          : merged;
      _episodeController.text = normalized.currentEpisode.toString();
      _privateReviewController.text = normalized.privateReview;
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail.copyWith(
          name: detail.name.isNotEmpty ? detail.name : (initial?.name ?? '未知番剧'),
          coverUrl: detail.coverUrl.isNotEmpty ? detail.coverUrl : (initial?.coverUrl ?? ''),
          airWeekday: resolvedWeekday,
          airDate: resolvedAirDate,
        );
        _progress = normalized;
        _selectedStatus = local?.statusSelected == true ? local!.status : null;
        _characters = characters;
        _characterLoadFailed = characterLoadFailed;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _statusLabel(WatchStatus status) {
    switch (status) {
      case WatchStatus.wish:
        return '想看';
      case WatchStatus.watching:
        return '在看';
      case WatchStatus.finished:
        return '已看完';
    }
  }

  Color _statusColor(WatchStatus status) {
    switch (status) {
      case WatchStatus.wish:
        return const Color(0xFFF9738A);
      case WatchStatus.watching:
        return const Color(0xFF22C7B8);
      case WatchStatus.finished:
        return const Color(0xFF8B6EFF);
    }
  }

  Color _statusSoftColor(WatchStatus status) {
    switch (status) {
      case WatchStatus.wish:
        return const Color(0xFFFFE4EA);
      case WatchStatus.watching:
        return const Color(0xFFE2FCF8);
      case WatchStatus.finished:
        return const Color(0xFFEAE4FF);
    }
  }

  Future<void> _saveProgress({required bool showTip}) async {
    final progress = _progress;
    if (progress == null) {
      return;
    }
    final hasReviewContent = progress.privateRating > 0 || progress.privateReview.trim().isNotEmpty;
    if (_selectedStatus == null) {
      if (hasReviewContent) {
        final next = WatchStatusReminderPolicy.normalize(
          progress.copyWith(statusSelected: false),
        );
        if (progress.reminderEnabled && !next.reminderEnabled) {
          await LocalNotificationService.instance.cancelReminder(next.subjectId);
        }
        await _watchlistStorage.upsert(next);
        return;
      }
      if (progress.reminderEnabled) {
        await LocalNotificationService.instance.cancelReminder(progress.subjectId);
      }
      await _watchlistStorage.delete(progress.subjectId);
      return;
    }
    final next = WatchStatusReminderPolicy.normalize(
      progress.copyWith(status: _selectedStatus, statusSelected: true),
    );
    if (progress.reminderEnabled && !next.reminderEnabled) {
      await LocalNotificationService.instance.cancelReminder(next.subjectId);
    }
    await _watchlistStorage.upsert(next);
    if (!mounted || !showTip) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('保存成功')),
    );
  }

  Future<void> _toggleReminder(bool enabled) async {
    final progress = _progress;
    if (progress == null) {
      return;
    }
    if (enabled &&
        !WatchStatusReminderPolicy.canEnableReminderForSelectedStatusName(
          _selectedStatus?.name,
        )) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('只有在看状态下才可开启更新提醒')),
      );
      return;
    }
    if (enabled && (progress.updateWeekday < 1 || progress.updateWeekday > 7)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该番剧暂无有效更新星期，无法开启提醒')),
      );
      return;
    }
    final next = progress.copyWith(reminderEnabled: enabled);
    _applyProgress(next, save: false);
    await _watchlistStorage.upsert(next);
    if (enabled) {
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
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(enabled ? '已开启更新提醒' : '已关闭更新提醒')),
    );
  }

  Future<void> _pickReminderTime() async {
    final progress = _progress;
    if (progress == null) {
      return;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: progress.reminderHour, minute: progress.reminderMinute),
      helpText: '选择提醒时间',
    );
    if (picked == null) {
      return;
    }
    final next = progress.copyWith(
      reminderHour: picked.hour,
      reminderMinute: picked.minute,
    );
    _applyProgress(next, save: false);
    await _watchlistStorage.upsert(next);
    if (next.reminderEnabled && next.updateWeekday >= 1 && next.updateWeekday <= 7) {
      await LocalNotificationService.instance.scheduleWeeklyReminder(
        subjectId: next.subjectId,
        animeName: next.name,
        airWeekday: next.updateWeekday,
        hour: next.reminderHour,
        minute: next.reminderMinute,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提醒时间已更新')),
      );
    }
  }

  void _applyProgress(AnimeProgress next, {bool save = true, bool syncSelectedStatus = false}) {
    final effectiveSelectedStatus = syncSelectedStatus ? next.status : _selectedStatus;
    final normalized = WatchStatusReminderPolicy.normalize(
      next.copyWith(
        status: effectiveSelectedStatus ?? next.status,
        statusSelected: effectiveSelectedStatus != null,
      ),
    );
    if (next.reminderEnabled && !normalized.reminderEnabled) {
      LocalNotificationService.instance.cancelReminder(normalized.subjectId);
    }
    setState(() {
      _progress = normalized;
      if (syncSelectedStatus) {
        _selectedStatus = effectiveSelectedStatus;
      }
      _episodeController.text = normalized.currentEpisode.toString();
    });
    if (save) {
      _saveProgress(showTip: false);
    }
  }

  void _increaseEpisode() {
    final progress = _progress;
    if (progress == null) {
      return;
    }
    HapticFeedback.lightImpact();
    int next = progress.currentEpisode + 1;
    if (progress.totalEpisodes > 0 && next > progress.totalEpisodes) {
      next = progress.totalEpisodes;
    }
    _applyProgress(
      progress.copyWith(currentEpisode: next),
      syncSelectedStatus: true,
    );
  }

  void _decreaseEpisode() {
    final progress = _progress;
    if (progress == null) {
      return;
    }
    HapticFeedback.lightImpact();
    var next = progress.currentEpisode - 1;
    if (next < 0) {
      next = 0;
    }
    final status = progress.totalEpisodes > 0 && next < progress.totalEpisodes && progress.status == WatchStatus.finished
        ? WatchStatus.watching
        : progress.status;
    _applyProgress(
      progress.copyWith(currentEpisode: next, status: status),
      syncSelectedStatus: true,
    );
  }

  void _addToFinished() {
    final progress = _progress;
    if (progress == null) {
      return;
    }
    HapticFeedback.mediumImpact();
    _applyProgress(
      progress.copyWith(status: WatchStatus.finished),
      syncSelectedStatus: true,
    );
  }

  void _updateEpisodeManually() {
    final progress = _progress;
    if (progress == null) {
      return;
    }
    HapticFeedback.selectionClick();
    int parsed = int.tryParse(_episodeController.text.trim()) ?? progress.currentEpisode;
    if (parsed < 0) {
      parsed = 0;
    }
    if (progress.totalEpisodes > 0 && parsed > progress.totalEpisodes) {
      parsed = progress.totalEpisodes;
    }
    final status = progress.totalEpisodes > 0 && parsed >= progress.totalEpisodes
        ? WatchStatus.finished
        : progress.status;
    _applyProgress(
      progress.copyWith(currentEpisode: parsed, status: status),
      syncSelectedStatus: true,
    );
  }

  Widget _buildInfoItem(String key, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EDF6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              key,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _submitPrivateReview() {
    final progress = _progress;
    if (progress == null) {
      return;
    }
    HapticFeedback.selectionClick();
    final review = _privateReviewController.text.trim();
    _applyProgress(progress.copyWith(privateReview: review));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('私密评价已保存')),
    );
  }

  void _deletePrivateReview() {
    final progress = _progress;
    if (progress == null || progress.privateReview.trim().isEmpty) {
      return;
    }
    HapticFeedback.selectionClick();
    _privateReviewController.clear();
    _applyProgress(progress.copyWith(privateReview: ''));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('私密评价已删除')),
    );
  }

  String _buildBilibiliSearchUrl(AnimeDetail detail) {
    final keyword = detail.name.trim().isNotEmpty ? detail.name.trim() : detail.originName.trim();
    if (keyword.isEmpty) {
      return '';
    }
    return 'https://search.bilibili.com/all?keyword=${Uri.encodeComponent(keyword)}';
  }

  Future<void> _openBilibiliSearch(AnimeDetail detail) async {
    final url = _buildBilibiliSearchUrl(detail);
    if (url.isEmpty) {
      return;
    }
    HapticFeedback.selectionClick();
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('打开 B 站失败')),
      );
    }
  }

  void _openImagePreview({
    required String imageUrl,
    required String heroTag,
  }) {
    if (imageUrl.trim().isEmpty) {
      return;
    }
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4,
                      child: Hero(
                        tag: heroTag,
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) {
                            return const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white70,
                              size: 64,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _handleDetailScroll(ScrollNotification notification) {
    final threshold = _detailHeaderExpandedHeight - kToolbarHeight - 4;
    final pinnedTop = notification.metrics.pixels >= threshold;
    if (pinnedTop != _isTitlePinnedTop && mounted) {
      setState(() {
        _isTitlePinnedTop = pinnedTop;
      });
    }
    return false;
  }

  Color _relationColor(String relation) {
    final text = relation.trim();
    if (text.contains('主角')) {
      return const Color(0xFF5B7CFA);
    }
    if (text.contains('配角')) {
      return const Color(0xFF16A34A);
    }
    return const Color(0xFF94A3B8);
  }

  Widget _buildCharactersSection(ThemeData theme) {
    if (_characters.isEmpty && !_characterLoadFailed) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('角色 & 声优', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_characterLoadFailed && _characters.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8EDF6)),
            ),
            child: const Text(
              '角色信息加载失败',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          )
        else
          SizedBox(
            height: 222,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _characters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final character = _characters[index];
                final relation = character.relation.trim().isEmpty ? '角色' : character.relation.trim();
                final relationColor = _relationColor(relation);
                final actorList = character.actors.take(2).toList();
                final actorDisplayList = actorList.where((item) => item.displayName.trim().isNotEmpty).toList();
                final actorSummary = actorList.isEmpty
                    ? ''
                    : actorList
                        .map((item) => item.summary.trim())
                        .where((item) => item.isNotEmpty)
                        .join(' / ');
                final roleSummary = character.summary.trim();
                final summaryText = roleSummary.isNotEmpty ? roleSummary : actorSummary;
                return Container(
                  width: 228,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE8EDF6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: GestureDetector(
                              onTap: character.imageUrl.isNotEmpty
                                  ? () => _openImagePreview(
                                        imageUrl: character.imageUrl,
                                        heroTag: 'character-image-${character.id}',
                                      )
                                  : null,
                              child: SizedBox(
                                width: 56,
                                height: 74,
                                child: character.imageUrl.isNotEmpty
                                    ? Hero(
                                        tag: 'character-image-${character.id}',
                                        child: Container(
                                          color: const Color(0xFFF8FAFF),
                                          alignment: Alignment.topCenter,
                                          child: Image.network(
                                            character.imageUrl,
                                            fit: BoxFit.contain,
                                            width: 56,
                                            height: 74,
                                            errorBuilder: (_, __, ___) {
                                              return Container(
                                                width: 56,
                                                height: 74,
                                                color: const Color(0xFFE2E8F0),
                                                alignment: Alignment.center,
                                                child: const Icon(Icons.person_outline, size: 22),
                                              );
                                            },
                                          ),
                                        ),
                                      )
                                    : Container(
                                        width: 56,
                                        height: 74,
                                        color: const Color(0xFFE2E8F0),
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.person_outline, size: 22),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  character.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: relationColor.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    relation,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: relationColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (actorDisplayList.isEmpty)
                        const Text(
                          '声优未知',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: actorDisplayList.map((actor) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFF),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ClipOval(
                                    child: actor.imageUrl.isNotEmpty
                                        ? Image.network(
                                            actor.imageUrl,
                                            width: 18,
                                            height: 18,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) {
                                              return Container(
                                                width: 18,
                                                height: 18,
                                                color: const Color(0xFFE2E8F0),
                                                alignment: Alignment.center,
                                                child: const Icon(Icons.person, size: 11),
                                              );
                                            },
                                          )
                                        : Container(
                                            width: 18,
                                            height: 18,
                                            color: const Color(0xFFE2E8F0),
                                            alignment: Alignment.center,
                                            child: const Icon(Icons.person, size: 11),
                                          ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    actor.displayName,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      if (summaryText.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          summaryText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  String _normalizeInfoboxKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(':', '')
        .replaceAll('：', '')
        .trim();
  }

  bool _matchesInfoboxKey(String key, List<String> candidates) {
    final normalizedKey = _normalizeInfoboxKey(key);
    for (final candidate in candidates) {
      if (normalizedKey.contains(_normalizeInfoboxKey(candidate))) {
        return true;
      }
    }
    return false;
  }

  List<int> _pickPreferredInfoboxIndexes(List<AnimeInfoboxItem> items) {
    final selected = <int>[];
    final preferredKeyGroups = <List<String>>[
      ['原作', '原著'],
      ['官网', '官方网站', '官方網站', 'officialsite', 'officialwebsite', '公式サイト'],
      ['导演', '導演', '监督', '監督'],
      ['脚本', '腳本', '剧本', '劇本'],
      ['系列构成', '系列構成', 'シリーズ構成'],
    ];
    for (final group in preferredKeyGroups) {
      var index = -1;
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        if (selected.contains(i)) {
          continue;
        }
        if (item.value.trim().isEmpty) {
          continue;
        }
        if (_matchesInfoboxKey(item.key, group)) {
          index = i;
          break;
        }
      }
      if (index >= 0 && !selected.contains(index)) {
        selected.add(index);
      }
    }
    return selected;
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final progress = _progress;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        _saveProgress(showTip: false);
      },
      child: Scaffold(
        body: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            if (_loading) {
              return ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: const [
                  _DetailSkeletonBlock(height: 280),
                  SizedBox(height: 14),
                  _DetailSkeletonBlock(height: 120),
                  SizedBox(height: 14),
                  _DetailSkeletonBlock(height: 180),
                ],
              );
            }
            if (_errorMessage != null) {
              if (NetworkErrorHelper.isNetworkErrorMessage(_errorMessage)) {
                return NoNetworkView(
                  onRetry: _loadData,
                  subtitle: '详情页内容需要联网加载',
                );
              }
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('加载失败\n$_errorMessage', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _loadData, child: const Text('重试')),
                  ],
                ),
              );
            }
            if (detail == null || progress == null) {
              return const Center(child: Text('暂无详情'));
            }
            final totalText = progress.totalEpisodes > 0 ? progress.totalEpisodes.toString() : '未知';
            final weeklyText = detail.airWeekday > 0 ? (_weekdayLabels[detail.airWeekday] ?? '未知') : '未知';
            final reminderTimeText =
                LocalNotificationService.formatReminderTimeText(progress.reminderHour, progress.reminderMinute);
            final showWatchingOnlySection = _selectedStatus == WatchStatus.watching;
            final normalizedSummary = detail.summary.trim();
            const summaryMarker = '[简介原文]';
            final markerIndex = normalizedSummary.indexOf(summaryMarker);
            final summaryMain = markerIndex >= 0 ? normalizedSummary.substring(0, markerIndex).trim() : normalizedSummary;
            final rawOriginalSummary =
                markerIndex >= 0 ? normalizedSummary.substring(markerIndex + summaryMarker.length).trim() : '';
            final summaryOriginal = rawOriginalSummary.isNotEmpty ? rawOriginalSummary : null;
            final preferredIndexes = _pickPreferredInfoboxIndexes(detail.infobox);
            final fallbackVisibleCount = detail.infobox.length >= 3 ? 3 : detail.infobox.length;
            final visibleIndexes = preferredIndexes.isNotEmpty
                ? preferredIndexes
                : List<int>.generate(fallbackVisibleCount, (index) => index);
            final visibleIndexSet = visibleIndexes.toSet();
            final visibleInfoboxItems = visibleIndexes.map((index) => detail.infobox[index]).toList();
            final hiddenInfoboxItems = <AnimeInfoboxItem>[];
            final hasSavedPrivateReview = progress.privateReview.trim().isNotEmpty;
            for (var i = 0; i < detail.infobox.length; i++) {
              if (!visibleIndexSet.contains(i)) {
                hiddenInfoboxItems.add(detail.infobox[i]);
              }
            }
            return NotificationListener<ScrollNotification>(
              onNotification: _handleDetailScroll,
              child: CustomScrollView(
                slivers: [
                SliverAppBar(
                  pinned: true,
                  centerTitle: true,
                  expandedHeight: _detailHeaderExpandedHeight,
                  backgroundColor: const Color(0xFFF5F7FA),
                  surfaceTintColor: Colors.transparent,
                  flexibleSpace: FlexibleSpaceBar(
                    centerTitle: true,
                    titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    title: Text(
                      detail.name,
                      textAlign: TextAlign.center,
                      softWrap: true,
                      maxLines: 3,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        color: _isTitlePinnedTop ? const Color(0xFF0F172A) : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        detail.coverUrl.isEmpty
                            ? Container(
                                color: const Color(0xFFCBD5E1),
                                alignment: Alignment.center,
                                child: const Icon(Icons.broken_image_outlined, size: 40),
                              )
                            : Image.network(
                                detail.coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: const Color(0xFFCBD5E1),
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.broken_image_outlined, size: 40),
                                  );
                                },
                              ),
                        Container(color: const Color(0x800F172A)),
                        SafeArea(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 112),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 270,
                                  maxHeight: 248,
                                ),
                                child: AspectRatio(
                                  aspectRatio: 2 / 3,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: GestureDetector(
                                      onTap: detail.coverUrl.isNotEmpty
                                          ? () => _openImagePreview(
                                                imageUrl: detail.coverUrl,
                                                heroTag: 'anime-cover-${detail.id}',
                                              )
                                          : null,
                                      child: Hero(
                                        tag: 'anime-cover-${detail.id}',
                                        child: detail.coverUrl.isEmpty
                                            ? Container(
                                                color: const Color(0xFFCBD5E1),
                                                alignment: Alignment.center,
                                                child: const Icon(Icons.broken_image_outlined, size: 34),
                                              )
                                            : Container(
                                                color: const Color(0xFF0F172A),
                                                alignment: Alignment.center,
                                                child: Image.network(
                                                  detail.coverUrl,
                                                  fit: BoxFit.contain,
                                                  width: double.infinity,
                                                  height: double.infinity,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return Container(
                                                      color: const Color(0xFFCBD5E1),
                                                      alignment: Alignment.center,
                                                      child: const Icon(Icons.broken_image_outlined, size: 34),
                                                    );
                                                  },
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5EAF4)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Bangumi评分', style: theme.textTheme.bodyMedium),
                                    const SizedBox(height: 4),
                                    Text(
                                      detail.ratingScore > 0 ? detail.ratingScore.toStringAsFixed(1) : '暂无',
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFFF59E0B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Bangumi排名', style: theme.textTheme.bodyMedium),
                                    const SizedBox(height: 4),
                                    Text(
                                      detail.ratingRank > 0 ? '#${detail.ratingRank}' : '暂无',
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF5B7CFA),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(label: Text('开播 ${detail.airDate.isEmpty ? '未知' : detail.airDate}')),
                            if (detail.platform.isNotEmpty) Chip(label: Text('平台 ${detail.platform}')),
                            if (detail.totalEpisodes > 0) Chip(label: Text('共 ${detail.totalEpisodes} 话')),
                          ],
                        ),
                        if (detail.originName.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text('原名：${detail.originName}', style: theme.textTheme.bodyMedium),
                        ],
                        const SizedBox(height: 18),
                        Text('简介', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          summaryMain.isNotEmpty ? summaryMain : '暂无简介',
                          style: theme.textTheme.bodyLarge,
                        ),
                        if (summaryOriginal != null) ...[
                          const SizedBox(height: 10),
                          Theme(
                            data: theme.copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              minTileHeight: 28,
                              visualDensity: const VisualDensity(vertical: -3),
                              childrenPadding: const EdgeInsets.only(bottom: 4),
                              backgroundColor: Colors.transparent,
                              collapsedBackgroundColor: Colors.transparent,
                              shape: const Border(),
                              collapsedShape: const Border(),
                              iconColor: const Color(0xFF94A3B8),
                              collapsedIconColor: const Color(0xFF94A3B8),
                              title: const Text(
                                '简介原文',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                              children: [
                                Text(
                                  summaryOriginal,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_buildBilibiliSearchUrl(detail).isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text('播放源', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE5EAF4)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Image.asset(
                                        'assets/icons/bilibili.png',
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.contain,
                                      ),
                                    ],
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: () => _openBilibiliSearch(detail),
                                  icon: const Icon(Icons.open_in_new_rounded),
                                  label: const Text('前往播放'),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text('观看状态', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Row(
                          children: WatchStatus.values.map((status) {
                            final selected = _selectedStatus == status;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () async {
                                    HapticFeedback.selectionClick();
                                    if (_selectedStatus == status) {
                                      final messenger = ScaffoldMessenger.of(context);
                                      final hasReviewContent =
                                          progress.privateRating > 0 || progress.privateReview.trim().isNotEmpty;
                                      final next = WatchStatusReminderPolicy.normalize(
                                        progress.copyWith(statusSelected: false),
                                      );
                                      setState(() {
                                        _selectedStatus = null;
                                        _progress = next;
                                      });
                                      if (hasReviewContent) {
                                        if (progress.reminderEnabled && !next.reminderEnabled) {
                                          await LocalNotificationService.instance.cancelReminder(next.subjectId);
                                        }
                                        await _watchlistStorage.upsert(next);
                                      } else {
                                        if (progress.reminderEnabled) {
                                          await LocalNotificationService.instance.cancelReminder(progress.subjectId);
                                        }
                                        await _watchlistStorage.delete(progress.subjectId);
                                      }
                                      if (!mounted) {
                                        return;
                                      }
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            hasReviewContent
                                                ? '已取消追番状态，已保留打分和评价并关闭提醒'
                                                : '已取消追番状态并关闭提醒',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    _applyProgress(
                                      progress.copyWith(status: status),
                                      syncSelectedStatus: true,
                                    );
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(vertical: 11),
                                    decoration: BoxDecoration(
                                      color: selected ? _statusColor(status) : _statusSoftColor(status),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _statusLabel(status),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: selected ? Colors.white : _statusColor(status),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        Text('私密评分', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Row(
                          children: List.generate(5, (index) {
                            final value = index + 1;
                            return IconButton(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                final nextRating = progress.privateRating == value ? 0 : value;
                                _applyProgress(progress.copyWith(privateRating: nextRating));
                              },
                              icon: Icon(
                                progress.privateRating >= value ? Icons.star : Icons.star_border,
                                color: Colors.amber,
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _privateReviewController,
                          maxLines: 3,
                          minLines: 2,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: '写下你对这部作品的私密评价',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF00BFFF), width: 1.2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (hasSavedPrivateReview) ...[
                              FilledButton.icon(
                                onPressed: _deletePrivateReview,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('删除评价'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                  backgroundColor: const Color(0xFFDC2626),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            FilledButton.tonalIcon(
                              onPressed: _submitPrivateReview,
                              icon: const Icon(Icons.lock_outline),
                              label: const Text('提交私密评价'),
                            ),
                          ],
                        ),
                        if (showWatchingOnlySection) ...[
                          const SizedBox(height: 20),
                          Text('观看进度', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text('已看 ${progress.currentEpisode} / $totalText 集', style: theme.textTheme.bodyLarge),
                          const SizedBox(height: 8),
                          TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 0,
                              end: progress.totalEpisodes > 0
                                  ? (progress.currentEpisode / progress.totalEpisodes).clamp(0, 1).toDouble()
                                  : 0,
                            ),
                            duration: const Duration(milliseconds: 350),
                            builder: (context, value, child) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: value,
                                  minHeight: 10,
                                  backgroundColor: const Color(0xFFE2FCF8),
                                  color: const Color(0xFF22C7B8),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 44,
                                  child: TextField(
                                    controller: _episodeController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: '手动集数'),
                                    onSubmitted: (_) => _updateEpisodeManually(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton.tonal(
                                onPressed: _updateEpisodeManually,
                                child: const Text('更新'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (progress.totalEpisodes > 0 && progress.currentEpisode >= progress.totalEpisodes)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _addToFinished,
                                icon: const Icon(Icons.done_all),
                                label: const Text('添加到已看完'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF8B6EFF),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(44),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                ),
                              ),
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    onPressed: _decreaseEpisode,
                                    icon: const Icon(Icons.remove),
                                    label: const Text('点击-1'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFFE2FCF8),
                                      foregroundColor: const Color(0xFF0F766E),
                                      minimumSize: const Size.fromHeight(44),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _increaseEpisode,
                                    icon: const Icon(Icons.add),
                                    label: const Text('点击+1'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF00BFFF),
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size.fromHeight(44),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 18),
                          Text('更新提醒', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFF),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE5EAF4)),
                            ),
                            child: Row(
                              children: [
                                Expanded(child: Text('每 $weeklyText $reminderTimeText 更新')),
                                TextButton(onPressed: _pickReminderTime, child: const Text('修改时间')),
                                Switch(value: progress.reminderEnabled, onChanged: _toggleReminder),
                              ],
                            ),
                          ),
                        ],
                        if (detail.tags.isNotEmpty || detail.metaTags.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text('标签', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: {
                              ...detail.tags,
                              ...detail.metaTags,
                            }.map((tag) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5FF),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  tag,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                        _buildCharactersSection(theme),
                        if (detail.infobox.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text('制作信息', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          ...visibleInfoboxItems.map((item) => _buildInfoItem(item.key, item.value)),
                          if (hiddenInfoboxItems.isNotEmpty)
                            Theme(
                              data: theme.copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                childrenPadding: EdgeInsets.zero,
                                backgroundColor: Colors.transparent,
                                collapsedBackgroundColor: Colors.transparent,
                                shape: const Border(),
                                collapsedShape: const Border(),
                                iconColor: const Color(0xFF64748B),
                                collapsedIconColor: const Color(0xFF64748B),
                                title: const Text(
                                  '展开更多制作信息',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                children: [
                                  ...hiddenInfoboxItems.map((item) => _buildInfoItem(item.key, item.value)),
                                ],
                              ),
                            ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DetailSkeletonBlock extends StatelessWidget {
  const _DetailSkeletonBlock({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE9EEF8),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
