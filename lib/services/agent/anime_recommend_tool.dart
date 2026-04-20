import 'dart:math' as math;

import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/models/anime_progress.dart';
import 'package:drama_tracker/services/agent/agent_models.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';

class AnimeRecommendTool extends AgentTool {
  static const int _maxTitleSeedQueries = 8;
  static const int _maxTagQueries = 12;
  static const int _maxDoubleTagQueries = 6;
  static const int _maxExecutedQueries = 12;

  AnimeRecommendTool(this._apiService, this._storage);

  final BangumiApiService _apiService;
  final WatchlistStorage _storage;

  @override
  String get name => 'AnimeRecommendTool';

  @override
  String get description => '仅用于基于用户本地追番历史、评分、状态、进度、短评与最近记录的细粒度偏好推荐，不适用于按标签、题材、年份或时间范围筛选。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'count': {'type': 'integer', 'description': '推荐数量，默认5'},
        },
      };

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> input) async {
    final all = _storage.getAllProgresses();
    if (all.isEmpty) {
      return const AgentToolResult(success: false, message: '暂无足够追番数据，建议先添加或评分一些番剧');
    }
    final rankedPreferences = [...all]
      ..sort((a, b) => _preferenceWeight(b).compareTo(_preferenceWeight(a)));
    final titleSeeds = _selectTitleSeeds(rankedPreferences);
    final preferenceTags = await _extractPreferenceTags(
      titleSeeds,
      fallbackProgresses: rankedPreferences,
    );
    final queries = await _buildTagQueries(
      titleSeeds: titleSeeds,
      extractedTags: preferenceTags,
    );
    if (queries.isEmpty) {
      return const AgentToolResult(success: false, message: '推荐失败：历史数据关键词不足');
    }
    try {
      final count = int.tryParse(input['count']?.toString() ?? '') ?? 5;
      final existed = all.map((e) => e.subjectId).toSet();
      final watchedTitleKeys = all
          .expand((e) => _watchKeysForTitle(e.name))
          .where((e) => e.isNotEmpty)
          .toSet();
      final candidateMap = <int, AnimeCalendarItem>{};
      final candidateScores = <int, double>{};
      final candidateSources = <int, Set<String>>{};
      for (final query in queries.take(_maxExecutedQueries)) {
        final page = await _searchCandidates(query);
        for (final item in page.data) {
          if (item.id <= 0 ||
              existed.contains(item.id) ||
              _belongsToWatchedSeries(item, watchedTitleKeys)) {
            continue;
          }
          final relevance = _candidateRelevance(query, item);
          if (relevance <= 0) {
            continue;
          }
          final qualityBoost = (item.ratingScore > 0 ? item.ratingScore / 10 : 0) * 0.35;
          final popularityBoost = item.doingCount > 0
              ? math.min(0.6, math.log(item.doingCount + 1) / 8)
              : 0.0;
          final score = (query.weight * relevance) + qualityBoost + popularityBoost;
          candidateMap[item.id] = item;
          candidateScores[item.id] = (candidateScores[item.id] ?? 0) + score;
          candidateSources.putIfAbsent(item.id, () => <String>{}).add(query.keyword);
        }
      }
      final filtered = candidateMap.values.toList()
        ..sort((a, b) => (candidateScores[b.id] ?? 0).compareTo(candidateScores[a.id] ?? 0));
      final finalItems = filtered.take(count.clamp(3, 12)).toList();
      final seedNames = titleSeeds.map((e) => e.name.trim()).where((e) => e.isNotEmpty).toList();
      final tagNames = queries
          .where((e) => e.mode == _PreferenceQueryMode.tag)
          .map((e) => e.keyword)
          .take(_maxTagQueries)
          .toList();
      return AgentToolResult(
        success: true,
        message: finalItems.isEmpty ? '暂时没有新的推荐，可以换个偏好再试' : '星奈结合你的评分、状态、进度和短评，为你整理了 ${finalItems.length} 部更可能喜欢的番剧',
        items: finalItems,
        payload: {
          'seedCount': seedNames.length,
          'seedNames': seedNames,
          'preferenceTags': tagNames,
          'queries': queries.map((e) => e.keyword).toList(),
          'matchedSources': {
            for (final entry in candidateSources.entries)
              entry.key.toString(): entry.value.toList(),
          },
          'strategy': 'rating+status+progress+review+recency',
        },
      );
    } catch (e) {
      return AgentToolResult(success: false, message: '推荐失败：$e');
    }
  }

  double _preferenceWeight(AnimeProgress progress) {
    final rating = progress.privateRating.clamp(0, 10).toDouble();
    final review = progress.privateReview.trim();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ageDays = progress.createdAtMs > 0
        ? math.max(0, ((nowMs - progress.createdAtMs) / Duration.millisecondsPerDay).floor())
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
      final ratio = (progress.currentEpisode / progress.totalEpisodes).clamp(0, 1);
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

  List<AnimeProgress> _selectTitleSeeds(List<AnimeProgress> rankedPreferences) {
    final seeds = <AnimeProgress>[];
    final seenSeries = <String>{};
    for (final progress in rankedPreferences) {
      final keyword = progress.name.trim();
      final seriesKey = _seriesKey(keyword);
      if (keyword.isEmpty || seriesKey.isEmpty || !seenSeries.add(seriesKey)) {
        continue;
      }
      seeds.add(progress);
      if (seeds.length >= _maxTitleSeedQueries) {
        break;
      }
    }
    return seeds;
  }

  Future<List<_PreferenceQuery>> _buildTagQueries({
    required List<AnimeProgress> titleSeeds,
    required List<String> extractedTags,
  }) async {
    final queries = <_PreferenceQuery>[];
    final seenLabels = <String>{};
    var comboQueryCount = 0;
    final tagPriority = <String, int>{
      for (var i = 0; i < extractedTags.length; i++) extractedTags[i]: i,
    };

    for (var i = 0; i < titleSeeds.length; i++) {
      final seed = titleSeeds[i];
      final seedTags = (await _loadCanonicalTags(
        progress: seed,
        vocabulary: extractedTags,
      ))
          .toList()
        ..sort((a, b) => (tagPriority[a] ?? 999).compareTo(tagPriority[b] ?? 999));
      if (seedTags.length < 2) {
        continue;
      }
      final comboTags = seedTags.take(2).toList();
      final label = comboTags.join(' + ');
      if (!seenLabels.add(label)) {
        continue;
      }
      queries.add(
        _PreferenceQuery(
          keyword: label,
          tags: comboTags,
          weight: math.max(3.2, 5.0 - (i * 0.35)),
          mode: _PreferenceQueryMode.tag,
        ),
      );
      comboQueryCount += 1;
      if (comboQueryCount >= _maxDoubleTagQueries ||
          queries.length >= _maxTagQueries) {
        return queries;
      }
    }

    for (var i = 0; i < math.min(extractedTags.length, _maxTagQueries); i++) {
      final tag = extractedTags[i];
      if (!seenLabels.add(tag)) {
        continue;
      }
      queries.add(
        _PreferenceQuery(
          keyword: tag,
          tags: <String>[tag],
          weight: math.max(1.6, 3.5 - (i * 0.3)),
          mode: _PreferenceQueryMode.tag,
        ),
      );
      if (queries.length >= _maxTagQueries) {
        break;
      }
    }
    return queries;
  }

  Future<AnimeSearchPage> _searchCandidates(_PreferenceQuery query) {
    switch (query.mode) {
      case _PreferenceQueryMode.tag:
        return _apiService.searchSubjects(
          keyword: '',
          tags: query.tags,
          limit: 10,
          offset: 0,
          sort: 'heat',
          rating: const ['>=6.5'],
          ratingCount: const ['>=100'],
        );
    }
  }

  double _candidateRelevance(_PreferenceQuery query, AnimeCalendarItem item) {
    switch (query.mode) {
      case _PreferenceQueryMode.tag:
        return 0.82 + math.min(0.18, (query.tags.length - 1) * 0.12);
    }
  }

  String _normalizeTitle(String value) {
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

  String _seriesKey(String value) {
    var normalized = _normalizeTitle(value);
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

  Set<String> _watchKeysForTitle(String value) {
    final normalized = _normalizeTitle(value);
    final series = _seriesKey(value);
    return <String>{normalized, series}.where((e) => e.isNotEmpty).toSet();
  }

  bool _belongsToWatchedSeries(
    AnimeCalendarItem item,
    Set<String> watchedTitleKeys,
  ) {
    final candidateKeys = _watchKeysForTitle(item.name);
    if (candidateKeys.isEmpty) {
      return false;
    }
    for (final candidateKey in candidateKeys) {
      for (final watchedKey in watchedTitleKeys) {
        if (_isSimilarFranchise(candidateKey, watchedKey)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isSimilarFranchise(String a, String b) {
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
    final prefixLength = _commonPrefixLength(a, b);
    final prefixRatio = prefixLength / shorter.length;
    if (prefixLength >= 6 && prefixRatio >= 0.45) {
      return true;
    }
    final overlap = _longestCommonSubstringLength(a, b);
    final overlapRatio = overlap / shorter.length;
    return overlap >= 4 && overlapRatio >= 0.7;
  }

  int _commonPrefixLength(String a, String b) {
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

  int _longestCommonSubstringLength(String a, String b) {
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

  Future<List<String>> _extractPreferenceTags(
    List<AnimeProgress> progresses, {
    List<AnimeProgress> fallbackProgresses = const [],
  }) async {
    const vocabulary = [
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
    final scores = <String, double>{};
    final seenIds = <int>{};
    final candidates = <AnimeProgress>[
      ...progresses,
      ...fallbackProgresses,
    ].where((progress) => seenIds.add(progress.subjectId)).take(20);
    for (final progress in candidates) {
      final weight = _preferenceWeight(progress);
      final matchedTags = await _loadCanonicalTags(
        progress: progress,
        vocabulary: vocabulary,
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

  Future<Set<String>> _loadCanonicalTags({
    required AnimeProgress progress,
    required List<String> vocabulary,
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
        for (final candidate in vocabulary) {
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
}

class _PreferenceQuery {
  const _PreferenceQuery({
    required this.keyword,
    required this.tags,
    required this.weight,
    required this.mode,
  });

  final String keyword;
  final List<String> tags;
  final double weight;
  final _PreferenceQueryMode mode;
}

enum _PreferenceQueryMode {
  tag,
}
