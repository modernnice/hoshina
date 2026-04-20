import 'package:drama_tracker/models/anime_progress.dart';
import 'package:drama_tracker/screens/anime_detail_page.dart';
import 'package:drama_tracker/services/cloud_sync_service.dart';
import 'package:drama_tracker/services/local_notification_service.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

class MyListPage extends StatefulWidget {
  const MyListPage({
    super.key,
    required this.onGoHome,
  });

  final VoidCallback onGoHome;

  @override
  State<MyListPage> createState() => _MyListPageState();
}

class _MyListPageState extends State<MyListPage> {
  final WatchlistStorage _storage = WatchlistStorage();
  final CloudSyncService _cloudSync = CloudSyncService.instance;
  late final ValueListenable<Box<Map>> _watchlistListenable;
  WatchStatus _tab = WatchStatus.watching;
  bool _showReviews = false;
  bool _gridMode = false;
  List<AnimeProgress> _items = [];

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
    _watchlistListenable = Hive.box<Map>('watchlist').listenable();
    _watchlistListenable.addListener(_reload);
    _reload();
    Future<void>.microtask(_syncFromCloudAndReload);
  }

  @override
  void dispose() {
    _watchlistListenable.removeListener(_reload);
    super.dispose();
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

  Future<void> _reload() async {
    final data = _showReviews
        ? _storage.getAllProgresses().where((item) => item.privateRating > 0 || item.privateReview.trim().isNotEmpty).toList()
        : _storage.getByStatus(_tab);
    data.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    if (!mounted) {
      return;
    }
    setState(() {
      _items = data;
    });
  }

  Future<void> _syncFromCloudAndReload() async {
    try {
      await _cloudSync.downloadToLocalPreferences(_storage);
    } catch (e) {
      debugPrint('Failed to sync watchlist from cloud: $e');
    }
    await _reload();
  }

  Future<void> _switchTab(WatchStatus status) async {
    HapticFeedback.selectionClick();
    setState(() {
      _tab = status;
    });
    await _reload();
  }

  Future<void> _switchMainMode(bool showReviews) async {
    HapticFeedback.selectionClick();
    setState(() {
      _showReviews = showReviews;
    });
    await _reload();
  }

  Future<void> _openDetail(AnimeProgress item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnimeDetailPage(subjectId: item.subjectId),
      ),
    );
    await _reload();
  }

  Future<void> _quickAddEpisode(AnimeProgress item) async {
    HapticFeedback.lightImpact();
    var nextEpisode = item.currentEpisode + 1;
    if (item.totalEpisodes > 0 && nextEpisode > item.totalEpisodes) {
      nextEpisode = item.totalEpisodes;
    }
    final nextStatus = item.totalEpisodes > 0 && nextEpisode >= item.totalEpisodes ? WatchStatus.finished : item.status;
    final next = item.copyWith(currentEpisode: nextEpisode, status: nextStatus);
    await _storage.upsert(next);
    await _reload();
  }

  Future<void> _moveToFinished(AnimeProgress item) async {
    HapticFeedback.mediumImpact();
    await _storage.upsert(item.copyWith(status: WatchStatus.finished));
    await _reload();
  }

  Future<void> _deleteItem(AnimeProgress item) async {
    await LocalNotificationService.instance.cancelReminder(item.subjectId);
    await _storage.delete(item.subjectId);
    await _reload();
  }

  Future<void> _deleteReviewOnly(AnimeProgress item) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('删除打分和评价'),
              content: const Text('仅删除该番剧的打分和评价内容，确认继续吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('删除'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirm) {
      return;
    }
    final next = item.copyWith(privateRating: 0, privateReview: '');
    if (!item.statusSelected) {
      await _storage.delete(item.subjectId);
    } else {
      await _storage.upsert(next);
    }
    await _reload();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除打分和评价')),
    );
  }

  Future<void> _changeStatus(AnimeProgress item) async {
    final selected = await showModalBottomSheet<WatchStatus>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: WatchStatus.values.map((status) {
              return ListTile(
                title: Text(_statusLabel(status)),
                trailing: item.status == status ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.of(context).pop(status);
                },
              );
            }).toList(),
          ),
        );
      },
    );
    if (selected == null || selected == item.status) {
      return;
    }
    await _storage.upsert(item.copyWith(status: selected));
    await _reload();
  }

  Future<bool> _onDismissed(AnimeProgress item, DismissDirection direction) async {
    if (direction == DismissDirection.endToStart) {
      final confirm = await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('删除追番'),
                content: const Text('确认删除该番并取消提醒吗？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('删除'),
                  ),
                ],
              );
            },
          ) ??
          false;
      if (!confirm) {
        return false;
      }
      await _deleteItem(item);
      return false;
    }
    await _changeStatus(item);
    return false;
  }

  Widget _buildTab() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          ...WatchStatus.values.map((status) {
            final selected = _tab == status;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _switchTab(status),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF00BFFF) : const Color(0xFFF2F5FB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF475569),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          IconButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                _gridMode = !_gridMode;
              });
            },
            icon: Icon(_gridMode ? Icons.view_list_rounded : Icons.grid_view_rounded),
            tooltip: _gridMode ? '切换列表视图' : '切换网格视图',
          ),
        ],
      ),
    );
  }

  Widget _buildMainModeTab() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 2),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _switchMainMode(false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !_showReviews ? const Color(0xFF00BFFF) : const Color(0xFFF2F5FB),
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  '我的追番',
                  style: TextStyle(
                    color: !_showReviews ? Colors.white : const Color(0xFF475569),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _switchMainMode(true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _showReviews ? const Color(0xFF00BFFF) : const Color(0xFFF2F5FB),
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  '我的打分和评价',
                  style: TextStyle(
                    color: _showReviews ? Colors.white : const Color(0xFF475569),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final theme = Theme.of(context);
    final title = _showReviews ? '暂无打分和评价' : '暂无${_statusLabel(_tab)}番剧';
    final subtitle = _showReviews ? '去详情页给喜欢的番剧打分和写评价吧' : '去首页挑一部番剧开始追更吧';
    final buttonText = _showReviews ? '去我的追番' : '去首页添加';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icons/mylist.png',
              width: 180,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) {
                return const Icon(Icons.bookmark_border_rounded, size: 56, color: Color(0xFF94A3B8));
              },
            ),
            const SizedBox(height: 10),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(subtitle, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _showReviews ? () => _switchMainMode(false) : widget.onGoHome,
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(AnimeProgress item, {double width = 72, double height = 96}) {
    final isWatching = item.status == WatchStatus.watching;
    final progressValue = item.totalEpisodes > 0 ? item.currentEpisode / item.totalEpisodes : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            Hero(
              tag: 'anime-cover-${item.subjectId}',
              child: item.coverUrl.isNotEmpty
                  ? Image.network(
                      item.coverUrl,
                      fit: BoxFit.cover,
                      width: width,
                      height: height,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    )
                  : Container(
                      color: Colors.grey.shade200,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
            ),
            if (isWatching)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                  color: const Color(0xB30F172A),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progressValue.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: Colors.white24,
                      color: const Color(0xFF22C7B8),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(AnimeProgress item) {
    final isWatching = item.status == WatchStatus.watching;
    final isProgressFull = item.totalEpisodes > 0 && item.currentEpisode >= item.totalEpisodes;
    final total = item.totalEpisodes > 0 ? item.totalEpisodes.toString() : '未知';
    final weekly = item.updateWeekday > 0 ? (_weekdayLabels[item.updateWeekday] ?? '未知') : '未知';
    final timeText = LocalNotificationService.formatReminderTimeText(item.reminderHour, item.reminderMinute);
    return Dismissible(
      key: ValueKey('my-${item.subjectId}'),
      background: Container(
        color: Colors.orange.shade100,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Text('修改状态'),
      ),
      secondaryBackground: Container(
        color: Colors.red.shade100,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Text('删除'),
      ),
      confirmDismiss: (direction) => _onDismissed(item, direction),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: InkWell(
          onTap: () => _openDetail(item),
          onLongPress: () => _changeStatus(item),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _buildCover(item),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name.isNotEmpty ? item.name : '未命名番剧',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      if (isWatching) ...[
                        const SizedBox(height: 6),
                        Text('已看 ${item.currentEpisode} / 共 $total 集'),
                        const SizedBox(height: 4),
                        Text('每周 $weekly 更新'),
                        const SizedBox(height: 4),
                        Text('提醒时间 $timeText'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isWatching)
                  isProgressFull
                      ? FilledButton.tonalIcon(
                          onPressed: () => _moveToFinished(item),
                          icon: const Icon(Icons.done_all),
                          label: const Text('移到已看完'),
                        )
                      : FilledButton.icon(
                          onPressed: () => _quickAddEpisode(item),
                          icon: const Icon(Icons.add),
                          label: const Text('点击+1'),
                        ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRatingStars(int rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final value = index + 1;
        return Icon(
          rating >= value ? Icons.star : Icons.star_border,
          size: 18,
          color: Colors.amber,
        );
      }),
    );
  }

  Widget _buildReviewItem(AnimeProgress item) {
    final review = item.privateReview.trim();
    final hasReview = review.isNotEmpty;
    final hasRating = item.privateRating > 0;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: InkWell(
        onTap: () => _openDetail(item),
        onLongPress: () => _deleteReviewOnly(item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCover(item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name.isNotEmpty ? item.name : '未命名番剧',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    if (hasRating) _buildRatingStars(item.privateRating),
                    if (hasReview) ...[
                      const SizedBox(height: 8),
                      Text(
                        review,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF475569), height: 1.4),
                      ),
                    ],
                    if (!hasReview && !hasRating)
                      const Text(
                        '暂无内容',
                        style: TextStyle(color: Color(0xFF94A3B8)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '我的追番',
              style: theme.textTheme.titleLarge,
            ),
          ),
        ),
        _buildMainModeTab(),
        if (!_showReviews) _buildTab(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _syncFromCloudAndReload,
            child: _items.isEmpty
                ? ListView(children: [SizedBox(height: MediaQuery.of(context).size.height * 0.5, child: _buildEmpty())])
                : _gridMode
                    ? GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.68,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final total = item.totalEpisodes > 0 ? '${item.totalEpisodes}' : '未知';
                          return Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _openDetail(item),
                              onLongPress: () => _changeStatus(item),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _buildCover(item, width: double.infinity, height: double.infinity)),
                                    const SizedBox(height: 8),
                                    Text(
                                      item.name.isNotEmpty ? item.name : '未命名番剧',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    if (_showReviews)
                                      _buildRatingStars(item.privateRating)
                                    else if (item.status == WatchStatus.watching)
                                      Text('${item.currentEpisode} / $total 集', style: theme.textTheme.bodyMedium),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          return _showReviews ? _buildReviewItem(_items[index]) : _buildItem(_items[index]);
                        },
                      ),
          ),
        ),
      ],
    );
  }
}
