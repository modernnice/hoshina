import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/screens/anime_detail_page.dart';
import 'package:drama_tracker/services/bangumi_api_service.dart';
import 'package:drama_tracker/services/watchlist_storage.dart';
import 'package:drama_tracker/utils/network_error_helper.dart';
import 'package:drama_tracker/widgets/anime_card.dart';
import 'package:drama_tracker/widgets/no_network_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final BangumiApiService _apiService = BangumiApiService();
  final WatchlistStorage _storage = WatchlistStorage();
  final TextEditingController _keywordController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<AnimeCalendarItem> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String _currentKeyword = '';
  int _offset = 0;
  int _limit = 20;
  int _total = 0;
  int _searchToken = 0;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 180) {
      _loadMore();
    }
  }

  Future<void> _search({bool refresh = true}) async {
    final inputKeyword = _keywordController.text.trim();
    final keyword = refresh ? inputKeyword : _currentKeyword;
    if (keyword.isEmpty) {
      setState(() {
        _items = [];
        _currentKeyword = '';
        _total = 0;
        _offset = 0;
        _error = null;
      });
      return;
    }
    final requestOffset = refresh ? 0 : _offset;
    final requestToken = refresh ? ++_searchToken : _searchToken;
    setState(() {
      _loading = true;
      _error = null;
      if (refresh) {
        _items = [];
        _offset = requestOffset;
        _total = 0;
        _currentKeyword = keyword;
      }
    });
    try {
      final page = await _apiService.searchSubjects(
        keyword: keyword,
        offset: requestOffset,
        limit: _limit,
      );
      if (!mounted || requestToken != _searchToken) {
        return;
      }
      setState(() {
        _limit = page.limit;
        final nextOffsetFromServer = page.offset + page.data.length;
        final nextOffset = nextOffsetFromServer > requestOffset ? nextOffsetFromServer : requestOffset + page.data.length;
        _offset = nextOffset;
        if (refresh) {
          final deduped = <AnimeCalendarItem>[];
          final ids = <int>{};
          for (final item in page.data) {
            if (ids.add(item.id)) {
              deduped.add(item);
            }
          }
          _items = deduped;
          _total = page.total;
        } else {
          final existingIds = _items.map((e) => e.id).toSet();
          var added = 0;
          for (final item in page.data) {
            if (existingIds.add(item.id)) {
              _items.add(item);
              added++;
            }
          }
          _total = added == 0 ? _items.length : page.total;
        }
      });
    } catch (e) {
      if (!mounted || requestToken != _searchToken) {
        return;
      }
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _currentKeyword.isEmpty) {
      return;
    }
    setState(() {
      _loadingMore = true;
    });
    await _search(refresh: false);
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

  Future<void> _saveStatus(AnimeCalendarItem item, WatchStatus status) async {
    HapticFeedback.selectionClick();
    final current = _storage.getStatus(item.id);
    final isCancel = current == status;
    if (isCancel) {
      await _storage.delete(item.id);
    } else {
      await _storage.save(item, status);
    }
    if (!mounted) {
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isCancel ? '已取消${_statusLabel(status)}：${item.name}' : '已添加到${_statusLabel(status)}：${item.name}',
        ),
      ),
    );
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
    setState(() {});
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    if (_loading && _items.isEmpty) {
      return ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 5,
        itemBuilder: (_, __) => const _SearchSkeletonCard(),
      );
    }
    if (_error != null && _items.isEmpty) {
      if (NetworkErrorHelper.isNetworkErrorMessage(_error)) {
        return NoNetworkView(
          onRetry: () => _search(refresh: true),
          subtitle: '请连接网络后再试一次搜索',
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('搜索失败\n$_error', textAlign: TextAlign.center),
              const SizedBox(height: 10),
              FilledButton(onPressed: _search, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_currentKeyword.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/icons/search_page.png',
                  width: 220,
                  height: 220,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) {
                    return const Icon(Icons.travel_explore_rounded, size: 72, color: Color(0xFF94A3B8));
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '发现你想看的番剧',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '输入关键词即可开始搜索',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 16,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sentiment_dissatisfied_rounded, size: 58, color: Color(0xFF94A3B8)),
              const SizedBox(height: 10),
              Text('没有找到相关番剧', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('可以换个关键词再试试', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _search(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final item = _items[index];
          return AnimeCard(
            item: item,
            currentStatus: _storage.getStatus(item.id),
            onTapWish: () => _saveStatus(item, WatchStatus.wish),
            onTapWatching: () => _saveStatus(item, WatchStatus.watching),
            onTapFinished: () => _saveStatus(item, WatchStatus.finished),
            onTapDetail: () => _openDetail(item),
            showSummary: true,
            showDoingCount: false,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('番剧搜索'),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keywordController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(refresh: true),
                    decoration: InputDecoration(
                      hintText: '输入番剧名，如：间谍过家家',
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF1F5FB),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(color: Color(0xFF00BFFF), width: 1.2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : () => _search(refresh: true),
                  icon: const Icon(Icons.search),
                  label: const Text('搜索'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}

class _SearchSkeletonCard extends StatelessWidget {
  const _SearchSkeletonCard();

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
