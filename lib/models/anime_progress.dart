import 'package:drama_tracker/services/watchlist_storage.dart';

class AnimeProgress {
  AnimeProgress({
    required this.subjectId,
    required this.name,
    required this.coverUrl,
    required this.currentEpisode,
    required this.totalEpisodes,
    required this.status,
    required this.statusSelected,
    required this.updateWeekday,
    required this.privateRating,
    required this.privateReview,
    required this.reminderEnabled,
    required this.reminderHour,
    required this.reminderMinute,
    required this.createdAtMs,
  });

  final int subjectId;
  final String name;
  final String coverUrl;
  final int currentEpisode;
  final int totalEpisodes;
  final WatchStatus status;
  final bool statusSelected;
  final int updateWeekday;
  final int privateRating;
  final String privateReview;
  final bool reminderEnabled;
  final int reminderHour;
  final int reminderMinute;
  final int createdAtMs;

  AnimeProgress copyWith({
    String? name,
    String? coverUrl,
    int? currentEpisode,
    int? totalEpisodes,
    WatchStatus? status,
    bool? statusSelected,
    int? updateWeekday,
    int? privateRating,
    String? privateReview,
    bool? reminderEnabled,
    int? reminderHour,
    int? reminderMinute,
    int? createdAtMs,
  }) {
    return AnimeProgress(
      subjectId: subjectId,
      name: name ?? this.name,
      coverUrl: coverUrl ?? this.coverUrl,
      currentEpisode: currentEpisode ?? this.currentEpisode,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      status: status ?? this.status,
      statusSelected: statusSelected ?? this.statusSelected,
      updateWeekday: updateWeekday ?? this.updateWeekday,
      privateRating: privateRating ?? this.privateRating,
      privateReview: privateReview ?? this.privateReview,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'subjectId': subjectId,
      'name': name,
      'coverUrl': coverUrl,
      'currentEpisode': currentEpisode,
      'totalEpisodes': totalEpisodes,
      'status': status.name,
      'statusSelected': statusSelected,
      'updateWeekday': updateWeekday,
      'privateRating': privateRating,
      'privateReview': privateReview,
      'reminderEnabled': reminderEnabled,
      'reminderHour': reminderHour,
      'reminderMinute': reminderMinute,
      'createdAtMs': createdAtMs,
    };
  }

  factory AnimeProgress.fromMap(Map<String, dynamic> map) {
    final rawStatus = map['status']?.toString() ?? '';
    WatchStatus status = WatchStatus.wish;
    for (final value in WatchStatus.values) {
      if (value.name == rawStatus) {
        status = value;
        break;
      }
    }
    return AnimeProgress(
      subjectId: int.tryParse((map['subjectId'] ?? map['id'] ?? 0).toString()) ?? 0,
      name: map['name']?.toString() ?? '未知番剧',
      coverUrl: map['coverUrl']?.toString() ?? '',
      currentEpisode: int.tryParse((map['currentEpisode'] ?? 0).toString()) ?? 0,
      totalEpisodes: int.tryParse((map['totalEpisodes'] ?? 0).toString()) ?? 0,
      status: status,
      statusSelected: map['statusSelected']?.toString() != 'false',
      updateWeekday: int.tryParse((map['updateWeekday'] ?? map['airWeekday'] ?? 0).toString()) ?? 0,
      privateRating: int.tryParse((map['privateRating'] ?? 0).toString()) ?? 0,
      privateReview: map['privateReview']?.toString() ?? '',
      reminderEnabled: (map['reminderEnabled'] ?? false).toString() == 'true',
      reminderHour: int.tryParse((map['reminderHour'] ?? 20).toString()) ?? 20,
      reminderMinute: int.tryParse((map['reminderMinute'] ?? 0).toString()) ?? 0,
      createdAtMs: int.tryParse((map['createdAtMs'] ?? 0).toString()) ?? 0,
    );
  }
}
