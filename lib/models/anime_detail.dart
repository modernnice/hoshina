class AnimeDetail {
  AnimeDetail({
    required this.id,
    required this.name,
    required this.originName,
    required this.coverUrl,
    required this.summary,
    required this.totalEpisodes,
    required this.airWeekday,
    required this.airDate,
    required this.date,
    required this.platform,
    required this.ratingScore,
    required this.ratingRank,
    required this.ratingTotal,
    required this.tags,
    required this.metaTags,
    required this.infobox,
    required this.collectionWish,
    required this.collectionDoing,
    required this.collectionCollect,
    required this.collectionOnHold,
    required this.collectionDropped,
  });

  final int id;
  final String name;
  final String originName;
  final String coverUrl;
  final String summary;
  final int totalEpisodes;
  final int airWeekday;
  final String airDate;
  final String date;
  final String platform;
  final double ratingScore;
  final int ratingRank;
  final int ratingTotal;
  final List<String> tags;
  final List<String> metaTags;
  final List<AnimeInfoboxItem> infobox;
  final int collectionWish;
  final int collectionDoing;
  final int collectionCollect;
  final int collectionOnHold;
  final int collectionDropped;

  AnimeDetail copyWith({
    String? name,
    String? coverUrl,
    int? airWeekday,
    String? airDate,
  }) {
    return AnimeDetail(
      id: id,
      name: name ?? this.name,
      originName: originName,
      coverUrl: coverUrl ?? this.coverUrl,
      summary: summary,
      totalEpisodes: totalEpisodes,
      airWeekday: airWeekday ?? this.airWeekday,
      airDate: airDate ?? this.airDate,
      date: date,
      platform: platform,
      ratingScore: ratingScore,
      ratingRank: ratingRank,
      ratingTotal: ratingTotal,
      tags: tags,
      metaTags: metaTags,
      infobox: infobox,
      collectionWish: collectionWish,
      collectionDoing: collectionDoing,
      collectionCollect: collectionCollect,
      collectionOnHold: collectionOnHold,
      collectionDropped: collectionDropped,
    );
  }

  factory AnimeDetail.fromJson(Map<String, dynamic> json) {
    final rawNameCn = json['name_cn']?.toString().trim();
    final rawName = json['name']?.toString().trim();
    final imageObj = json['images'];
    final ratingObj = json['rating'];
    final collectionObj = json['collection'];
    final parsedCover = imageObj is Map<String, dynamic>
        ? imageObj['common']?.toString().trim() ?? ''
        : '';
    final parsedRating = ratingObj is Map<String, dynamic>
        ? double.tryParse(ratingObj['score']?.toString() ?? '') ?? 0.0
        : 0.0;
    final parsedRank = ratingObj is Map<String, dynamic>
        ? int.tryParse((ratingObj['rank'] ?? 0).toString()) ?? 0
        : 0;
    final parsedTotal = ratingObj is Map<String, dynamic>
        ? int.tryParse((ratingObj['total'] ?? 0).toString()) ?? 0
        : 0;
    final parsedTags = _parseTags(json['tags']);
    final parsedMetaTags = _parseMetaTags(json['meta_tags']);
    final parsedInfobox = _parseInfobox(json['infobox']);
    final parsedWeekday = int.tryParse((json['air_weekday'] ?? 0).toString()) ?? 0;
    final rawAirDate = (json['air_date'] ?? json['date'] ?? '').toString().trim();
    final derivedWeekday = _weekdayFromDate(rawAirDate);
    final parsedDate = (json['date'] ?? '').toString().trim();
    return AnimeDetail(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: (rawNameCn?.isNotEmpty ?? false) ? rawNameCn! : (rawName ?? '未知番剧'),
      originName: rawName ?? '',
      coverUrl: parsedCover,
      summary: json['summary']?.toString().trim().isNotEmpty == true
          ? json['summary'].toString().trim()
          : '暂无简介',
      totalEpisodes: int.tryParse((json['total_episodes'] ?? 0).toString()) ?? 0,
      airWeekday: parsedWeekday < 1 || parsedWeekday > 7 ? derivedWeekday : parsedWeekday,
      airDate: rawAirDate,
      date: parsedDate,
      platform: (json['platform'] ?? '').toString(),
      ratingScore: parsedRating,
      ratingRank: parsedRank,
      ratingTotal: parsedTotal,
      tags: parsedTags,
      metaTags: parsedMetaTags,
      infobox: parsedInfobox,
      collectionWish: collectionObj is Map<String, dynamic>
          ? int.tryParse((collectionObj['wish'] ?? 0).toString()) ?? 0
          : 0,
      collectionDoing: collectionObj is Map<String, dynamic>
          ? int.tryParse((collectionObj['doing'] ?? 0).toString()) ?? 0
          : 0,
      collectionCollect: collectionObj is Map<String, dynamic>
          ? int.tryParse((collectionObj['collect'] ?? 0).toString()) ?? 0
          : 0,
      collectionOnHold: collectionObj is Map<String, dynamic>
          ? int.tryParse((collectionObj['on_hold'] ?? 0).toString()) ?? 0
          : 0,
      collectionDropped: collectionObj is Map<String, dynamic>
          ? int.tryParse((collectionObj['dropped'] ?? 0).toString()) ?? 0
          : 0,
    );
  }

  static int _weekdayFromDate(String value) {
    if (value.isEmpty) {
      return 0;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return 0;
    }
    final weekday = parsed.weekday;
    return weekday < 1 || weekday > 7 ? 0 : weekday;
  }

  static List<String> _parseTags(dynamic raw) {
    if (raw is! List) {
      return [];
    }
    final list = <String>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        final value = item['name']?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          list.add(value);
        }
      }
    }
    return list;
  }

  static List<String> _parseMetaTags(dynamic raw) {
    if (raw is! List) {
      return [];
    }
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static List<AnimeInfoboxItem> _parseInfobox(dynamic raw) {
    if (raw is! List) {
      return [];
    }
    final list = <AnimeInfoboxItem>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final key = item['key']?.toString().trim() ?? '';
      final value = _parseInfoboxValue(item['value']);
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      list.add(AnimeInfoboxItem(key: key, value: value));
    }
    return list;
  }

  static String _parseInfoboxValue(dynamic raw) {
    if (raw == null) {
      return '';
    }
    if (raw is String) {
      return raw.trim();
    }
    if (raw is List) {
      final values = <String>[];
      for (final item in raw) {
        if (item is String && item.trim().isNotEmpty) {
          values.add(item.trim());
        } else if (item is Map<String, dynamic>) {
          final v = item['v']?.toString().trim() ?? '';
          if (v.isNotEmpty) {
            values.add(v);
          }
        }
      }
      return values.join(' / ');
    }
    if (raw is Map<String, dynamic>) {
      return raw['v']?.toString().trim() ?? '';
    }
    return raw.toString().trim();
  }
}

class AnimeInfoboxItem {
  AnimeInfoboxItem({
    required this.key,
    required this.value,
  });

  final String key;
  final String value;
}

class AnimeCharacter {
  AnimeCharacter({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.relation,
    required this.imageUrl,
    required this.actors,
  });

  final int id;
  final String name;
  final String nameCn;
  final String summary;
  final String relation;
  final String imageUrl;
  final List<AnimeActor> actors;

  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  int get rolePriority {
    final text = relation.trim();
    if (text.contains('主角')) {
      return 0;
    }
    if (text.contains('配角')) {
      return 1;
    }
    return 2;
  }

  static int compareByRolePriority(AnimeCharacter a, AnimeCharacter b) {
    final roleCompare = a.rolePriority.compareTo(b.rolePriority);
    if (roleCompare != 0) {
      return roleCompare;
    }
    final relationCompare = a.relation.trim().compareTo(b.relation.trim());
    if (relationCompare != 0) {
      return relationCompare;
    }
    final nameCompare = a.displayName.compareTo(b.displayName);
    if (nameCompare != 0) {
      return nameCompare;
    }
    return a.id.compareTo(b.id);
  }

  factory AnimeCharacter.fromJson(Map<String, dynamic> json) {
    final imageObj = json['images'];
    final imageUrl = imageObj is Map<String, dynamic>
        ? (imageObj['medium']?.toString().trim().isNotEmpty == true
            ? imageObj['medium'].toString().trim()
            : imageObj['small']?.toString().trim() ?? '')
        : '';
    final relationRaw = (json['relation'] ?? json['staff'] ?? '').toString().trim();
    final relation = relationRaw.isNotEmpty ? relationRaw : _relationFromType(json['type']);
    final actorsRaw = json['actors'];
    final actors = <AnimeActor>[];
    if (actorsRaw is List) {
      for (final item in actorsRaw) {
        if (item is Map<String, dynamic>) {
          final actor = AnimeActor.fromJson(item);
          if (actor.isSeiyu || actor.careers.isEmpty) {
            actors.add(actor);
          }
        }
      }
    }
    return AnimeCharacter(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      name: json['name']?.toString().trim() ?? '',
      nameCn: json['name_cn']?.toString().trim() ?? '',
      summary: json['summary']?.toString().trim() ?? '',
      relation: relation,
      imageUrl: imageUrl,
      actors: actors,
    );
  }

  static String _relationFromType(dynamic value) {
    final type = int.tryParse((value ?? 0).toString()) ?? 0;
    if (type == 1) {
      return '主角';
    }
    if (type == 2) {
      return '配角';
    }
    if (type == 3) {
      return '客串';
    }
    return '';
  }
}

class AnimeActor {
  AnimeActor({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.imageUrl,
    required this.careers,
  });

  final int id;
  final String name;
  final String nameCn;
  final String summary;
  final String imageUrl;
  final List<String> careers;

  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  bool get isSeiyu {
    return careers.any((item) {
      final v = item.toLowerCase();
      return v == 'seiyu' || v.contains('声优') || v.contains('聲優');
    });
  }

  factory AnimeActor.fromJson(Map<String, dynamic> json) {
    final imageObj = json['images'];
    final imageUrl = imageObj is Map<String, dynamic>
        ? (imageObj['medium']?.toString().trim().isNotEmpty == true
            ? imageObj['medium'].toString().trim()
            : imageObj['small']?.toString().trim() ?? '')
        : '';
    final careersRaw = json['career'];
    final careers = <String>[];
    if (careersRaw is List) {
      for (final item in careersRaw) {
        final v = item.toString().trim();
        if (v.isNotEmpty) {
          careers.add(v);
        }
      }
    } else if (careersRaw != null) {
      final v = careersRaw.toString().trim();
      if (v.isNotEmpty) {
        careers.add(v);
      }
    }
    return AnimeActor(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      name: json['name']?.toString().trim() ?? '',
      nameCn: json['name_cn']?.toString().trim() ?? '',
      summary: json['summary']?.toString().trim() ?? '',
      imageUrl: imageUrl,
      careers: careers,
    );
  }
}
