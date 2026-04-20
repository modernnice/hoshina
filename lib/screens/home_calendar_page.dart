import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/screens/anime_detail_page.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';
import 'package:drama_tracker/utils/network_error_helper.dart';
import 'package:drama_tracker/widgets/anime_card.dart';
import 'package:drama_tracker/widgets/draggable_rebound_image.dart';
import 'package:drama_tracker/widgets/no_network_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomeCalendarPage extends StatefulWidget {
  const HomeCalendarPage({super.key});

  @override
  State<HomeCalendarPage> createState() => _HomeCalendarPageState();
}

class _HomeCalendarPageState extends State<HomeCalendarPage> {
  final BangumiApiService _apiService = BangumiApiService();
  final WatchlistStorage _watchlistStorage = WatchlistStorage();
  final Map<int, List<AnimeCalendarItem>> _groupedByWeekday = {};

  bool _loading = true;
  String? _errorMessage;
  int _selectedWeekday = DateTime.now().weekday.clamp(1, 7);

  static const Map<int, String> _weekdayLabels = {
    1: '一·月',
    2: '二·火',
    3: '三·水',
    4: '四·木',
    5: '五·金',
    6: '六·土',
    7: '七·日',
  };
  static const List<int> _weekdayOrder = [1, 2, 3, 4, 5, 6, 7];
  static const double _titleLeftOffset = 34;
  static const double _topIconLeft = 250;
  static const double _topIconTop = -60;
  static const double _topIconSize = 100;

  @override
  void initState() {
    super.initState();
    _loadCalendar();
  }

  void _safeSetState(VoidCallback fn) {
    Future<void>.delayed(const Duration(milliseconds: 1), () {
      if (!mounted) {
        return;
      }
      setState(fn);
    });
  }

  Future<void> _loadCalendar() async {
    _safeSetState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final items = await _apiService.fetchWeeklyCalendar();
      final grouped = <int, List<AnimeCalendarItem>>{
        for (var i = 1; i <= 7; i++) i: <AnimeCalendarItem>[],
      };
      for (final item in items) {
        grouped[item.airWeekday]?.add(item);
      }
      _safeSetState(() {
        _groupedByWeekday
          ..clear()
          ..addAll(grouped);
      });
    } catch (e) {
      _safeSetState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        _safeSetState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveStatus(AnimeCalendarItem item, WatchStatus status) async {
    HapticFeedback.selectionClick();
    final current = _watchlistStorage.getStatus(item.id);
    final isCancel = current == status;
    if (isCancel) {
      await _watchlistStorage.delete(item.id);
    } else {
      await _watchlistStorage.save(item, status);
    }
    if (!mounted) {
      return;
    }
    _safeSetState(() {});
    Future<void>.delayed(const Duration(milliseconds: 1), () {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCancel
                ? '已取消${_statusLabel(status)}：${item.name}'
                : '已添加到${_statusLabel(status)}：${item.name}',
          ),
        ),
      );
    });
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

  Future<void> _openDetail(AnimeCalendarItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnimeDetailPage(
          subjectId: item.id,
          initialCalendarItem: item,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    _safeSetState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final currentItems = _groupedByWeekday[_selectedWeekday] ?? <AnimeCalendarItem>[];
    final overlayTop = media.padding.top + kToolbarHeight + _topIconTop;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Scaffold(
          appBar: AppBar(
            centerTitle: false,
            title: const Padding(
              padding: EdgeInsets.only(left: _titleLeftOffset),
              child: Text('本周新番时间表'),
            ),
          ),
          body: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: SizedBox(
                  height: 48,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) {
                      final day = _weekdayOrder[index];
                      final selected = day == _selectedWeekday;
                      return InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () {
                          if (_selectedWeekday == day || !mounted) {
                            return;
                          }
                          HapticFeedback.selectionClick();
                          Future<void>.delayed(const Duration(milliseconds: 1), () {
                            if (!mounted) {
                              return;
                            }
                            setState(() {
                              _selectedWeekday = day;
                            });
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF00BFFF) : const Color(0xFFF2F5FB),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _weekdayLabels[day] ?? '',
                            style: TextStyle(
                              color: selected ? Colors.white : const Color(0xFF475569),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemCount: _weekdayOrder.length,
                  ),
                ),
              ),
              Expanded(
                child: Builder(
                  builder: (context) {
                if (_loading) {
                  return ListView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 5,
                    itemBuilder: (_, __) => const _AnimeCardSkeleton(),
                  );
                }
                if (_errorMessage != null) {
                  if (NetworkErrorHelper.isNetworkErrorMessage(_errorMessage)) {
                    return NoNetworkView(
                      onRetry: _loadCalendar,
                      subtitle: '当前无法连接网络，请检查后重试',
                    );
                  }
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '加载失败\n$_errorMessage',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadCalendar,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  );
                }
                if (currentItems.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.movie_creation_outlined,
                            size: 56,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(height: 10),
                          Text('这一天还没有新番', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 6),
                          Text(
                            '换一天看看，或者下拉刷新获取最新数据',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: _loadCalendar,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: currentItems.length,
                    itemBuilder: (context, index) {
                      final item = currentItems[index];
                      return AnimeCard(
                        item: item,
                        currentStatus: _watchlistStorage.getStatus(item.id),
                        onTapWish: () => _saveStatus(item, WatchStatus.wish),
                        onTapWatching: () => _saveStatus(item, WatchStatus.watching),
                        onTapFinished: () => _saveStatus(item, WatchStatus.finished),
                        onTapDetail: () => _openDetail(item),
                        showDoingCount: false,
                      );
                    },
                  ),
                );
                  },
                ),
              ),
            ],
          ),
        ),
        DraggableReboundImage(
          assetPath: 'assets/icons/top.png',
          left: _topIconLeft,
          top: overlayTop,
          size: _topIconSize,
          maxDragDistance: 260,
        ),
      ],
    );
  }
}

class _AnimeCardSkeleton extends StatelessWidget {
  const _AnimeCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 92,
              height: 122,
              decoration: BoxDecoration(
                color: const Color(0xFFE9EEF8),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(4, (index) {
                  final widths = [0.7, 0.5, 0.9, 0.55];
                  final heights = [16.0, 12.0, 12.0, 30.0];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FractionallySizedBox(
                      widthFactor: widths[index],
                      child: Container(
                        height: heights[index],
                        decoration: BoxDecoration(
                          color: const Color(0xFFE9EEF8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
