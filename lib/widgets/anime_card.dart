import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';
import 'package:flutter/material.dart';

class AnimeCard extends StatelessWidget {
  const AnimeCard({
    super.key,
    required this.item,
    required this.currentStatus,
    required this.onTapWish,
    required this.onTapWatching,
    required this.onTapFinished,
    required this.onTapDetail,
    this.showSummary = false,
    this.showDoingCount = true,
  });

  final AnimeCalendarItem item;
  final WatchStatus? currentStatus;
  final VoidCallback onTapWish;
  final VoidCallback onTapWatching;
  final VoidCallback onTapFinished;
  final VoidCallback onTapDetail;
  final bool showSummary;
  final bool showDoingCount;

  static const Color _wishColor = Color(0xFFF9738A);
  static const Color _wishSoft = Color(0xFFFFE4EA);
  static const Color _watchingColor = Color(0xFF22C7B8);
  static const Color _watchingSoft = Color(0xFFE2FCF8);
  static const Color _finishedColor = Color(0xFF8B6EFF);
  static const Color _finishedSoft = Color(0xFFEAE4FF);

  Color _scoreColor(double score) {
    if (score >= 8) {
      return Colors.green;
    }
    if (score >= 7) {
      return Colors.lightGreen;
    }
    if (score >= 6) {
      return Colors.orange;
    }
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scoreText = item.ratingScore > 0 ? item.ratingScore.toStringAsFixed(1) : '暂无';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTapDetail,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Hero(
                  tag: 'anime-cover-${item.id}',
                  child: SizedBox(
                    width: 92,
                    height: 122,
                    child: item.coverUrl.isEmpty
                        ? Container(
                            color: Colors.grey.shade200,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_outlined, size: 28),
                          )
                        : Image.network(
                            item.coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey.shade200,
                                alignment: Alignment.center,
                                child: const Icon(Icons.broken_image_outlined, size: 28),
                              );
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 3),
                        Text(
                          'Bangumi $scoreText',
                          style: TextStyle(
                            color: _scoreColor(item.ratingScore),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MetaTag(
                          label: '开播 ${item.airDate.isEmpty ? '未知' : item.airDate}',
                          background: const Color(0xFFF2F5FF),
                        ),
                        if (showDoingCount)
                          _MetaTag(
                            label: '在看 ${item.doingCount}',
                            background: const Color(0xFFE8FDF9),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (showSummary && item.summary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _StatusButton(
                          label: '想看',
                          selected: currentStatus == WatchStatus.wish,
                          selectedColor: _wishColor,
                          softColor: _wishSoft,
                          onTap: onTapWish,
                        ),
                        _StatusButton(
                          label: '在看',
                          selected: currentStatus == WatchStatus.watching,
                          selectedColor: _watchingColor,
                          softColor: _watchingSoft,
                          onTap: onTapWatching,
                        ),
                        _StatusButton(
                          label: '已看完',
                          selected: currentStatus == WatchStatus.finished,
                          selectedColor: _finishedColor,
                          softColor: _finishedSoft,
                          onTap: onTapFinished,
                        ),
                      ],
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
}

class _MetaTag extends StatelessWidget {
  const _MetaTag({
    required this.label,
    required this.background,
  });

  final String label;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF475569),
        ),
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.softColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final Color softColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? selectedColor : softColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? selectedColor : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : selectedColor,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
