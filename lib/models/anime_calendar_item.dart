class AnimeCalendarItem {
  AnimeCalendarItem({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.airWeekday,
    required this.airDate,
    required this.ratingScore,
    required this.doingCount,
    this.summary = '',
    this.totalEpisodes = 0,
  });

  final int id;
  final String name;
  final String coverUrl;
  final int airWeekday;
  final String airDate;
  final double ratingScore;
  final int doingCount;
  final String summary;
  final int totalEpisodes;

  factory AnimeCalendarItem.fromJson(Map<String, dynamic> json) {
    final rawNameCn = json['name_cn']?.toString().trim();
    final rawName = json['name']?.toString().trim();
    final imageObj = json['images'];
    final ratingObj = json['rating'];
    final collectionObj = json['collection'];

    final parsedCover = imageObj is Map<String, dynamic>
        ? imageObj['common']?.toString().trim() ?? ''
        : '';

    final double parsedRating = ratingObj is Map<String, dynamic>
        ? double.tryParse(ratingObj['score']?.toString() ?? '') ?? 0.0
        : 0.0;

    final parsedDoing = collectionObj is Map<String, dynamic>
        ? int.tryParse(collectionObj['doing']?.toString() ?? '') ?? 0
        : 0;

    final parsedWeekday = int.tryParse(json['air_weekday']?.toString() ?? '') ?? 0;
    final normalizedWeekday = parsedWeekday < 0 ? 0 : (parsedWeekday > 7 ? 7 : parsedWeekday);

    final rawAirDate = json['air_date']?.toString().trim() ?? '';
    final rawDate = json['date']?.toString().trim() ?? '';

    return AnimeCalendarItem(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: (rawNameCn?.isNotEmpty ?? false) ? rawNameCn! : (rawName ?? '未知番剧'),
      coverUrl: parsedCover,
      airWeekday: normalizedWeekday,
      airDate: rawAirDate.isNotEmpty ? rawAirDate : rawDate,
      ratingScore: parsedRating,
      doingCount: parsedDoing,
      summary: json['summary']?.toString().trim() ?? '',
      totalEpisodes: int.tryParse((json['total_episodes'] ?? 0).toString()) ?? 0,
    );
  }
}
