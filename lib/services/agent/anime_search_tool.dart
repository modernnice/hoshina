import 'package:drama_tracker/services/agent/anime_recommendation_support.dart';
import 'package:drama_tracker/services/agent/agent_models.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';

class AnimeSearchTool extends AgentTool {
  AnimeSearchTool(this._apiService, this._storage)
      : _support = AnimeRecommendationSupport(_apiService, _storage);

  final BangumiApiService _apiService;
  final WatchlistStorage _storage;
  final AnimeRecommendationSupport _support;

  @override
  String get name => 'AnimeSearchTool';

  @override
  String get description =>
      '根据关键词、标签、元标签、年份、评分或排名条件搜索番剧。也可用于推荐场景：通过 excludeWatched / excludeSameSeries 自动排除用户已添加和同系列作品。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'keyword': {'type': 'string', 'description': '搜索关键词'},
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '标签关键词列表（会映射到 tag）',
          },
          'metaTags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '元标签，如 原创/漫画改',
          },
          'tag': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '标签，如 治愈/校园',
          },
          'airDate': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '播出时间条件，如 [">=2023-01-01","<2024-01-01"]',
          },
          'rating': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '评分条件，如 [">=7","<9"]',
          },
          'ratingCount': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '评分人数条件，如 [">=200"]',
          },
          'rank': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '排名条件，如 [">10","<=100"]',
          },
          'nsfw': {'type': 'boolean', 'description': '是否包含 NSFW'},
          'limit': {'type': 'integer', 'description': '返回数量，默认 10'},
          'offset': {'type': 'integer', 'description': '分页偏移，默认 0'},
          'sort': {
            'type': 'string',
            'enum': ['rank', 'heat'],
            'description': '排序方式，默认 rank',
          },
          'excludeWatched': {
            'type': 'boolean',
            'description': '是否自动排除用户已添加到追番列表中的作品，推荐场景建议开启',
          },
          'excludeSameSeries': {
            'type': 'boolean',
            'description': '是否自动排除与用户现有追番属于同系列/IP 的作品，推荐场景建议开启',
          },
          'recommendationMode': {
            'type': 'boolean',
            'description':
                '推荐模式。开启后若未显式提供 rating / ratingCount，会默认补充 >=6.5 和 >=100 的推荐门槛',
          },
        },
      };

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> input) async {
    final keyword = input['keyword']?.toString().trim() ?? '';
    final tags = _toStringList(input['tags']);
    final tag = _toStringList(input['tag']);
    final metaTags = _toStringList(input['metaTags']);
    final airDate = _toStringList(input['airDate']);
    final rating = _toStringList(input['rating']);
    final ratingCount = _toStringList(input['ratingCount']);
    final rank = _toStringList(input['rank']);
    final excludeWatched = input['excludeWatched'] == true;
    final excludeSameSeries = input['excludeSameSeries'] == true;
    final recommendationMode = input['recommendationMode'] == true;
    final hasAnyFilter = tags.isNotEmpty ||
        tag.isNotEmpty ||
        metaTags.isNotEmpty ||
        airDate.isNotEmpty ||
        rating.isNotEmpty ||
        ratingCount.isNotEmpty ||
        rank.isNotEmpty ||
        input['nsfw'] != null;
    if (keyword.isEmpty && !hasAnyFilter) {
      return const AgentToolResult(success: false, message: '请提供关键词或至少一个筛选条件');
    }
    final mergedTag =
        [...tags, ...tag].where((e) => e.isNotEmpty).toSet().toList();
    final limit =
        (int.tryParse(input['limit']?.toString() ?? '') ?? 10).clamp(1, 50);
    final offset = int.tryParse(input['offset']?.toString() ?? '') ?? 0;
    final sort = input['sort']?.toString() == 'heat' ? 'heat' : 'rank';
    final effectiveRating =
        recommendationMode && rating.isEmpty ? const <String>['>=6.5'] : rating;
    final effectiveRatingCount = recommendationMode && ratingCount.isEmpty
        ? const <String>['>=100']
        : ratingCount;
    final filter = <String, dynamic>{
      'type': [2],
      if (metaTags.isNotEmpty) 'meta_tags': metaTags,
      if (mergedTag.isNotEmpty) 'tag': mergedTag,
      if (airDate.isNotEmpty) 'air_date': airDate,
      if (effectiveRating.isNotEmpty) 'rating': effectiveRating,
      if (effectiveRatingCount.isNotEmpty) 'rating_count': effectiveRatingCount,
      if (rank.isNotEmpty) 'rank': rank,
      if (input['nsfw'] is bool) 'nsfw': input['nsfw'],
    };
    final body = <String, dynamic>{
      'keyword': keyword,
      'sort': sort,
      'filter': filter,
      'limit': limit,
      'offset': offset,
    };
    try {
      final page = await _apiService.searchSubjects(
        keyword: keyword,
        limit: limit,
        offset: offset,
        sort: sort,
        tags: mergedTag,
        metaTags: metaTags,
        airDate: airDate,
        rating: effectiveRating,
        ratingCount: effectiveRatingCount,
        rank: rank,
        nsfw: input['nsfw'] is bool ? input['nsfw'] as bool : null,
      );
      final allProgresses = _storage.getAllProgresses();
      final existedSubjectIds = excludeWatched
          ? _support.watchedSubjectIds(allProgresses)
          : const <int>{};
      final watchedTitleKeys = (excludeWatched || excludeSameSeries)
          ? _support.watchedTitleKeys(allProgresses)
          : const <String>{};
      final filteredResults = (excludeWatched || excludeSameSeries)
          ? page.data.where((item) {
              if (excludeWatched && existedSubjectIds.contains(item.id)) {
                return false;
              }
              if (excludeSameSeries &&
                  _support.belongsToWatchedSeries(item, watchedTitleKeys)) {
                return false;
              }
              return true;
            }).toList()
          : page.data;
      final limitedResults = filteredResults.take(limit).toList();
      return AgentToolResult(
        success: true,
        message: limitedResults.isEmpty
            ? '没有找到符合条件的番剧'
            : '找到 ${limitedResults.length} 部番剧',
        items: limitedResults,
        payload: {
          'request': page.request.isEmpty ? body : page.request,
          'total': page.total,
          'recommendationMode': recommendationMode,
          'excludeWatched': excludeWatched,
          'excludeSameSeries': excludeSameSeries,
        },
      );
    } catch (e) {
      return AgentToolResult(success: false, message: '搜索失败：$e');
    }
  }

  List<String> _toStringList(dynamic raw) {
    if (raw is! List) {
      return <String>[];
    }
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
