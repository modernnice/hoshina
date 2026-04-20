import 'dart:math' as math;

import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/models/anime_detail.dart';
import 'package:drama_tracker/screens/anime_detail_page.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/utils/network_error_helper.dart';
import 'package:drama_tracker/widgets/draggable_rebound_image.dart';
import 'package:drama_tracker/widgets/no_network_view.dart';
import 'package:flutter/material.dart';

enum _HeatPeriod { quarter, year }

class HeatRankingPage extends StatefulWidget {
  const HeatRankingPage({super.key});

  @override
  State<HeatRankingPage> createState() => _HeatRankingPageState();
}

class _HeatRankingPageState extends State<HeatRankingPage> {
  final BangumiApiService _apiService = BangumiApiService();

  bool _loading = true;
  String? _errorMessage;
  _HeatPeriod _period = _HeatPeriod.quarter;
  List<_HeatRankItem> _quarterRanking = [];
  List<_HeatRankItem> _yearRanking = [];
  late DateTime _quarterStart;
  late DateTime _yearStart;
  late DateTime _today;
  static const double _titleLeftOffset = 34;
  static const double _topIconLeft = 250;
  static const double _topIconTop = -60;
  static const double _topIconSize = 100;

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    final quarterStartMonth = ((_today.month - 1) ~/ 3) * 3 + 1;
    _quarterStart = DateTime(_today.year, quarterStartMonth, 1);
    _yearStart = DateTime(_today.year, 1, 1);
    _loadRankings();
  }

  Future<void> _loadRankings() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    try {
      final quarter = await _buildRanking(
        startDate: _quarterStart,
        endDate: _today,
        maxPages: 10,
      );
      final year = await _buildRanking(
        startDate: _yearStart,
        endDate: _today,
        maxPages: 20,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _quarterRanking = quarter;
        _yearRanking = year;
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

  Future<List<_HeatRankItem>> _buildRanking({
    required DateTime startDate,
    required DateTime endDate,
    required int maxPages,
  }) async {
    final candidates = await _apiService.searchAnimeByAirDateRange(
      startDate: startDate,
      endDate: endDate,
      maxPages: maxPages,
      pageSize: 50,
    );
    if (candidates.isEmpty) {
      return [];
    }
    final filtered = candidates.where((item) => _isInRange(item.airDate, startDate, endDate)).toList();
    filtered.sort((a, b) => b.doingCount.compareTo(a.doingCount));
    final preselected = filtered.take(80).toList();
    final rankItems = <_HeatRankItem>[];
    for (final candidate in preselected) {
      try {
        final detail = await _apiService.fetchSubjectDetail(candidate.id);
        final score = _heatScore(detail);
        rankItems.add(_HeatRankItem(
          source: candidate,
          detail: detail,
          score: score,
        ));
      } catch (_) {
        continue;
      }
    }
    rankItems.sort((a, b) => b.score.compareTo(a.score));
    if (rankItems.length > 30) {
      return rankItems.sublist(0, 30);
    }
    return rankItems;
  }

  bool _isInRange(String dateText, DateTime start, DateTime end) {
    if (dateText.trim().isEmpty) {
      return false;
    }
    final parsed = DateTime.tryParse(dateText);
    if (parsed == null) {
      return false;
    }
    final d = DateTime(parsed.year, parsed.month, parsed.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  double _heatScore(AnimeDetail detail) {
    final doing = math.log(detail.collectionDoing + 1) * 42;
    final wish = math.log(detail.collectionWish + 1) * 24;
    final collect = math.log(detail.collectionCollect + 1) * 19;
    final ratingCount = math.log(detail.ratingTotal + 1) * 7;
    final ratingScore = detail.ratingScore * 8;
    final droppedPenalty = math.log(detail.collectionDropped + 1) * 6;
    final holdPenalty = math.log(detail.collectionOnHold + 1) * 3.5;
    return doing + wish + collect + ratingCount + ratingScore - droppedPenalty - holdPenalty;
  }

  String _formatDate(DateTime value) {
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '${value.year}.$m.$d';
  }

  String _rangeText() {
    final start = _period == _HeatPeriod.quarter ? _quarterStart : _yearStart;
    return '${_formatDate(start)} - ${_formatDate(_today)}';
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
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final ranking = _period == _HeatPeriod.quarter ? _quarterRanking : _yearRanking;
    final overlayTop = media.padding.top + kToolbarHeight + _topIconTop;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Scaffold(
          appBar: AppBar(
            centerTitle: false,
            title: const Padding(
              padding: EdgeInsets.only(left: _titleLeftOffset),
              child: Text('热度排行榜'),
            ),
          ),
          body: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(14, 10, 14, 8),
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
                        onTap: () {
                          if (_period == _HeatPeriod.quarter) {
                            return;
                          }
                          setState(() {
                            _period = _HeatPeriod.quarter;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _period == _HeatPeriod.quarter
                                ? const Color(0xFF00BFFF)
                                : const Color(0xFFF2F5FB),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '本季度',
                            style: TextStyle(
                              color: _period == _HeatPeriod.quarter
                                  ? Colors.white
                                  : const Color(0xFF475569),
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
                        onTap: () {
                          if (_period == _HeatPeriod.year) {
                            return;
                          }
                          setState(() {
                            _period = _HeatPeriod.year;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _period == _HeatPeriod.year
                                ? const Color(0xFF00BFFF)
                                : const Color(0xFFF2F5FB),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '本年度',
                            style: TextStyle(
                              color: _period == _HeatPeriod.year
                                  ? Colors.white
                                  : const Color(0xFF475569),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '统计区间：${_rangeText()}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadRankings,
                  child: Builder(
                    builder: (context) {
                  if (_loading) {
                    return ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: 6,
                      itemBuilder: (_, __) {
                        return Container(
                          height: 118,
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                        );
                      },
                    );
                  }
                  if (_errorMessage != null) {
                    if (NetworkErrorHelper.isNetworkErrorMessage(_errorMessage)) {
                      return NoNetworkView(
                        onRetry: _loadRankings,
                        subtitle: '排行榜需要联网获取数据',
                      );
                    }
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('加载失败\n$_errorMessage', textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                FilledButton(onPressed: _loadRankings, child: const Text('重试')),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  if (ranking.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: const Center(
                            child: Text('当前区间暂无可统计的热度数据'),
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: ranking.length + 1,
                    itemBuilder: (context, index) {
                      if (index == ranking.length) {
                        return const Padding(
                          padding: EdgeInsets.fromLTRB(16, 10, 16, 24),
                          child: Text(
                            '热度数据基于 Bangumi 公开数据（在看/想看/看过、评分人数、评分分数、搁置/抛弃）按加权模型计算，仅供追番参考。',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                              height: 1.45,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      final item = ranking[index];
                      final rank = index + 1;
                      final badgeColor = switch (rank) {
                        1 => const Color(0xFFEF4444),
                        2 => const Color(0xFFF97316),
                        3 => const Color(0xFFEAB308),
                        _ => const Color(0xFF94A3B8),
                      };
                      final airDate = item.source.airDate.isNotEmpty ? item.source.airDate : '未知';
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _openDetail(item.source),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '$rank',
                                    style: TextStyle(
                                      color: badgeColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: item.source.coverUrl.isNotEmpty
                                      ? Image.network(
                                          item.source.coverUrl,
                                          width: 68,
                                          height: 90,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) {
                                            return Container(
                                              width: 68,
                                              height: 90,
                                              color: const Color(0xFFE2E8F0),
                                              alignment: Alignment.center,
                                              child: const Icon(Icons.broken_image_outlined),
                                            );
                                          },
                                        )
                                      : Container(
                                          width: 68,
                                          height: 90,
                                          color: const Color(0xFFE2E8F0),
                                          alignment: Alignment.center,
                                          child: const Icon(Icons.broken_image_outlined),
                                        ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.source.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '开播：$airDate',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '在看 ${item.detail.collectionDoing}  想看 ${item.detail.collectionWish}  看过 ${item.detail.collectionCollect}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF475569),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '热度分 ${item.score.toStringAsFixed(1)}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF5B7CFA),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                    },
                  ),
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

class _HeatRankItem {
  _HeatRankItem({
    required this.source,
    required this.detail,
    required this.score,
  });

  final AnimeCalendarItem source;
  final AnimeDetail detail;
  final double score;
}
