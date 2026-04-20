import 'dart:math' as math;

import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/models/anime_progress.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';

class AnimeRecommendationSupport {
  AnimeRecommendationSupport(this._apiService, this._storage);

  static const List<String> vocabulary = <String>[
    '治愈',
    '热血',
    '科幻',
    '恋爱',
    '校园',
    '悬疑',
    '推理',
    '奇幻',
    '冒险',
    '日常',
    '机战',
    '搞笑',
    '战斗',
    '异世界',
    '百合',
    '运动',
    '历史',
    '催泪',
    '剧情',
    '群像',
    '音乐',
    '成长',
  ];

  final BangumiApiService _apiService;
  final WatchlistStorage _storage;

  List<AnimeProgress> getAllProgresses() => _storage.getAllProgresses();

  List<AnimeProgress> getRankedPreferences() {
    final ranked = [...getAllProgresses()]
      ..sort((a, b) => preferenceWeight(b).compareTo(preferenceWeight(a)));
    return ranked;
  }

  double preferenceWeight(AnimeProgress progress) {
    final rating = progress.privateRating.clamp(0, 10).toDouble();
    final review = progress.privateReview.trim();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ageDays = progress.createdAtMs > 0
        ? math.max(
            0,
            ((nowMs - progress.createdAtMs) / Duration.millisecondsPerDay)
                .floor())
        : 9999;

    var score = 0.0;
    score += rating * 2.4;

    switch (progress.status) {
      case WatchStatus.finished:
        score += 3.0;
      case WatchStatus.watching:
        score += 2.4;
      case WatchStatus.wish:
        score += 0.8;
    }

    if (progress.totalEpisodes > 0) {
      final ratio =
          (progress.currentEpisode / progress.totalEpisodes).clamp(0, 1);
      score += ratio * 2.2;
    } else if (progress.currentEpisode > 0) {
      score += 0.8;
    }

    if (review.isNotEmpty) {
      score += review.length >= 20 ? 1.5 : 0.8;
    }
    if (progress.reminderEnabled) {
      score += 0.4;
    }
    if (ageDays <= 30) {
      score += 1.4;
    } else if (ageDays <= 90) {
      score += 1.0;
    } else if (ageDays <= 180) {
      score += 0.6;
    }
    return score;
  }

  List<AnimeProgress> selectTitleSeeds(
    List<AnimeProgress> rankedPreferences, {
    int limit = 8,
  }) {
    final seeds = <AnimeProgress>[];
    final seenSeries = <String>{};
    for (final progress in rankedPreferences) {
      final keyword = progress.name.trim();
      final normalizedSeriesKey = seriesKey(keyword);
      if (keyword.isEmpty ||
          normalizedSeriesKey.isEmpty ||
          !seenSeries.add(normalizedSeriesKey)) {
        continue;
      }
      seeds.add(progress);
      if (seeds.length >= limit) {
        break;
      }
    }
    return seeds;
  }

  Future<List<String>> extractPreferenceTags(
    List<AnimeProgress> progresses, {
    List<AnimeProgress> fallbackProgresses = const [],
  }) async {
    final scores = <String, double>{};
    final seenIds = <int>{};
    final candidates = <AnimeProgress>[
      ...progresses,
      ...fallbackProgresses,
    ].where((progress) => seenIds.add(progress.subjectId)).take(20);
    for (final progress in candidates) {
      final weight = preferenceWeight(progress);
      final matchedTags = await loadCanonicalTags(
        progress: progress,
        vocabularyList: vocabulary,
      );
      if (matchedTags.isNotEmpty) {
        for (final tag in matchedTags) {
          scores[tag] = (scores[tag] ?? 0) + weight;
        }
        continue;
      }
      final fallbackText = '${progress.name} ${progress.privateReview}'.trim();
      if (fallbackText.isEmpty) {
        continue;
      }
      for (final tag in vocabulary) {
        if (fallbackText.contains(tag)) {
          scores[tag] = (scores[tag] ?? 0) + weight;
        }
      }
    }
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).toList();
  }

  Future<Set<String>> loadCanonicalTags({
    required AnimeProgress progress,
    required List<String> vocabularyList,
  }) async {
    if (progress.subjectId <= 0) {
      return <String>{};
    }
    try {
      final detail = await _apiService.fetchSubjectDetail(progress.subjectId);
      final rawTags = <String>{
        ...detail.tags,
        ...detail.metaTags,
      };
      final matched = <String>{};
      for (final rawTag in rawTags) {
        final normalizedTag = rawTag.trim();
        if (normalizedTag.isEmpty) {
          continue;
        }
        for (final candidate in vocabularyList) {
          if (normalizedTag == candidate || normalizedTag.contains(candidate)) {
            matched.add(candidate);
          }
        }
      }
      return matched;
    } catch (_) {
      return <String>{};
    }
  }

  Set<int> watchedSubjectIds(List<AnimeProgress> progresses) =>
      progresses.map((e) => e.subjectId).where((e) => e > 0).toSet();

  Set<String> watchedTitleKeys(List<AnimeProgress> progresses) {
    return progresses
        .expand((e) => watchKeysForTitle(e.name))
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  List<AnimeCalendarItem> filterOutWatchedAndSameSeries(
    List<AnimeCalendarItem> items, {
    required Set<int> existedSubjectIds,
    required Set<String> watchedTitleKeys,
  }) {
    final filtered = <AnimeCalendarItem>[];
    for (final item in items) {
      if (item.id <= 0 ||
          existedSubjectIds.contains(item.id) ||
          belongsToWatchedSeries(item, watchedTitleKeys)) {
        continue;
      }
      filtered.add(item);
    }
    return filtered;
  }

  String normalizeTitle(String value) {
    var normalized = value.toLowerCase().trim();
    if (normalized.isEmpty) {
      return '';
    }
    normalized = normalized
        .replaceAll(RegExp(r'[!！?？:：·・,，.。/\\\-\s]+'), '')
        .replaceAll(RegExp(r'第[0-9一二三四五六七八九十]+季'), '')
        .replaceAll(RegExp(r'season\s*\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'(tv|ova|oad|web)'), '')
        .replaceAll(RegExp(r'(剧场版|特别篇|特典|总集篇)'), '');
    return normalized;
  }

  String seriesKey(String value) {
    var normalized = normalizeTitle(value);
    if (normalized.isEmpty) {
      return '';
    }
    normalized = normalized
        .replaceAll(RegExp(r'第[0-9一二三四五六七八九十]+期'), '')
        .replaceAll(RegExp(r'第[0-9一二三四五六七八九十]+部'), '')
        .replaceAll(RegExp(r'[0-9]+$'), '')
        .replaceAll(RegExp(r'(前篇|后篇|上篇|下篇|完结篇)$'), '')
        .replaceAll(RegExp(r'(season)$', caseSensitive: false), '');
    return normalized;
  }

  Set<String> watchKeysForTitle(String value) {
    final normalized = normalizeTitle(value);
    final series = seriesKey(value);
    return <String>{normalized, series}.where((e) => e.isNotEmpty).toSet();
  }

  bool belongsToWatchedSeries(
    AnimeCalendarItem item,
    Set<String> watchedTitleKeys,
  ) {
    final candidateKeys = watchKeysForTitle(item.name);
    if (candidateKeys.isEmpty) {
      return false;
    }
    for (final candidateKey in candidateKeys) {
      for (final watchedKey in watchedTitleKeys) {
        if (isSimilarFranchise(candidateKey, watchedKey)) {
          return true;
        }
      }
    }
    return false;
  }

  bool isSimilarFranchise(String a, String b) {
    if (a.isEmpty || b.isEmpty) {
      return false;
    }
    if (a == b) {
      return true;
    }
    final shorter = a.length <= b.length ? a : b;
    final longer = a.length <= b.length ? b : a;
    if (shorter.length < 4) {
      return false;
    }
    if (longer.contains(shorter)) {
      return true;
    }
    final prefixLength = commonPrefixLength(a, b);
    final prefixRatio = prefixLength / shorter.length;
    if (prefixLength >= 6 && prefixRatio >= 0.45) {
      return true;
    }
    final overlap = longestCommonSubstringLength(a, b);
    final overlapRatio = overlap / shorter.length;
    return overlap >= 4 && overlapRatio >= 0.7;
  }

  int commonPrefixLength(String a, String b) {
    final maxLength = math.min(a.length, b.length);
    var matched = 0;
    for (var i = 0; i < maxLength; i++) {
      if (a.codeUnitAt(i) != b.codeUnitAt(i)) {
        break;
      }
      matched += 1;
    }
    return matched;
  }

  int longestCommonSubstringLength(String a, String b) {
    if (a.isEmpty || b.isEmpty) {
      return 0;
    }
    final dp = List<List<int>>.generate(
      a.length + 1,
      (_) => List<int>.filled(b.length + 1, 0),
    );
    var best = 0;
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        if (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
          if (dp[i][j] > best) {
            best = dp[i][j];
          }
        }
      }
    }
    return best;
  }
}
