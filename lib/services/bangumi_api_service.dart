import 'dart:convert';

import 'package:drama_tracker/models/anime_calendar_item.dart';
import 'package:drama_tracker/models/anime_detail.dart';
import 'package:http/http.dart' as http;

class BangumiApiService {
  static const String _baseUrl = 'https://api.bgm.tv';

  Future<List<AnimeCalendarItem>> fetchWeeklyCalendar() async {
    final uri = Uri.parse('$_baseUrl/calendar');
    final response = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'DramaTracker/1.0 (Flutter)',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('请求失败：${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic>) {
      throw Exception('数据格式错误');
    }

    final allItems = <AnimeCalendarItem>[];
    for (final dayObj in decoded) {
      if (dayObj is! Map<String, dynamic>) {
        continue;
      }
      final items = dayObj['items'];
      if (items is! List<dynamic>) {
        continue;
      }
      for (final item in items) {
        if (item is Map<String, dynamic>) {
          allItems.add(AnimeCalendarItem.fromJson(item));
        }
      }
    }
    return allItems;
  }

  Future<AnimeDetail> fetchSubjectDetail(int id) async {
    final uri = Uri.parse('$_baseUrl/v0/subjects/$id');
    final response = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'DramaTracker/1.0 (Flutter)',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('详情请求失败：${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('详情数据格式错误');
    }
    return AnimeDetail.fromJson(decoded);
  }

  Future<List<AnimeCharacter>> fetchSubjectCharacters(int id) async {
    final uri = Uri.parse('$_baseUrl/v0/subjects/$id/characters');
    final response = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'DramaTracker/1.0 (Flutter)',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('角色请求失败：${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic>) {
      throw Exception('角色数据格式错误');
    }
    final list = <AnimeCharacter>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        final character = AnimeCharacter.fromJson(item);
        if (character.id <= 0) {
          continue;
        }
        if (character.imageUrl.trim().isEmpty) {
          continue;
        }
        if (character.displayName.trim().isEmpty) {
          continue;
        }
        list.add(character);
      }
    }
    return list;
  }

  Future<AnimeCharacterSearchPage> searchCharacters({
    required String keyword,
    int limit = 20,
    int offset = 0,
    bool? nsfw,
  }) async {
    final uri = Uri.parse('$_baseUrl/v0/search/characters');
    final body = <String, dynamic>{
      'keyword': keyword,
      'filter': {
        if (nsfw != null) 'nsfw': nsfw,
      },
    };
    final response = await http.post(
      uri.replace(
        queryParameters: <String, String>{
          'limit': limit.toString(),
          'offset': offset.toString(),
        },
      ),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'DramaTracker/1.0 (Flutter)',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('角色搜索请求失败：${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('角色搜索数据格式错误');
    }
    final rawData = decoded['data'];
    final list = <AnimeCharacter>[];
    if (rawData is List) {
      for (final item in rawData) {
        if (item is Map<String, dynamic>) {
          final character = AnimeCharacter.fromJson(item);
          if (character.id <= 0) {
            continue;
          }
          if (character.displayName.trim().isEmpty) {
            continue;
          }
          list.add(character);
        }
      }
    }
    return AnimeCharacterSearchPage(
      total: int.tryParse((decoded['total'] ?? 0).toString()) ?? 0,
      limit: int.tryParse((decoded['limit'] ?? limit).toString()) ?? limit,
      offset: int.tryParse((decoded['offset'] ?? offset).toString()) ?? offset,
      data: list.take(limit).toList(),
      request: {
        'keyword': keyword,
        'filter': {
          if (nsfw != null) 'nsfw': nsfw,
        },
        'limit': limit,
        'offset': offset,
      },
    );
  }

  Future<BangumiPersonSearchPage> searchPersons({
    required String keyword,
    int limit = 20,
    int offset = 0,
    List<String> careers = const [],
  }) async {
    final uri = Uri.parse('$_baseUrl/v0/search/persons');
    final normalizedCareers = careers
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final body = <String, dynamic>{
      'keyword': keyword,
      'filter': {
        if (normalizedCareers.isNotEmpty) 'career': normalizedCareers,
      },
    };
    final response = await http.post(
      uri.replace(
        queryParameters: <String, String>{
          'limit': limit.toString(),
          'offset': offset.toString(),
        },
      ),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'DramaTracker/1.0 (Flutter)',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('人物搜索请求失败：${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('人物搜索数据格式错误');
    }
    final rawData = decoded['data'];
    final list = <BangumiPerson>[];
    if (rawData is List) {
      for (final item in rawData) {
        if (item is Map<String, dynamic>) {
          final person = BangumiPerson.fromJson(item);
          if (person.id <= 0) {
            continue;
          }
          if (person.displayName.trim().isEmpty) {
            continue;
          }
          list.add(person);
        }
      }
    }
    return BangumiPersonSearchPage(
      total: int.tryParse((decoded['total'] ?? 0).toString()) ?? 0,
      limit: int.tryParse((decoded['limit'] ?? limit).toString()) ?? limit,
      offset: int.tryParse((decoded['offset'] ?? offset).toString()) ?? offset,
      data: list.take(limit).toList(),
      request: {
        'keyword': keyword,
        'filter': {
          if (normalizedCareers.isNotEmpty) 'career': normalizedCareers,
        },
        'limit': limit,
        'offset': offset,
      },
    );
  }

  Future<List<PersonRelatedCharacter>> fetchPersonRelatedCharacters(
    int personId,
  ) async {
    final uri = Uri.parse('$_baseUrl/v0/persons/$personId/characters');
    final response = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'DramaTracker/1.0 (Flutter)',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('人物关联角色请求失败：${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic>) {
      throw Exception('人物关联角色数据格式错误');
    }
    final list = <PersonRelatedCharacter>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        final character = PersonRelatedCharacter.fromJson(item);
        if (character.id <= 0) {
          continue;
        }
        if (character.displayName.trim().isEmpty) {
          continue;
        }
        list.add(character);
      }
    }
    return list;
  }

  Future<AnimeSearchPage> searchSubjects({
    required String keyword,
    int limit = 20,
    int offset = 0,
    String sort = 'rank',
    List<String> tags = const [],
    List<String> metaTags = const [],
    List<String> airDate = const [],
    List<String> rating = const [],
    List<String> ratingCount = const [],
    List<String> rank = const [],
    bool? nsfw,
  }) async {
    final uri = Uri.parse('$_baseUrl/v0/search/subjects');
    final normalizedSort = sort == 'heat' ? 'heat' : 'rank';
    final body = {
      'keyword': keyword,
      'sort': normalizedSort,
      'filter': {
        'type': [2],
        if (metaTags.isNotEmpty) 'meta_tags': metaTags,
        if (tags.isNotEmpty) 'tag': tags,
        if (airDate.isNotEmpty) 'air_date': airDate,
        if (rating.isNotEmpty) 'rating': rating,
        if (ratingCount.isNotEmpty) 'rating_count': ratingCount,
        if (rank.isNotEmpty) 'rank': rank,
        if (nsfw != null) 'nsfw': nsfw,
      },
      'limit': limit,
      'offset': offset,
    };
    final response = await http.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'DramaTracker/1.0 (Flutter)',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('搜索请求失败：${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('搜索数据格式错误');
    }
    final rawData = decoded['data'];
    final list = <AnimeCalendarItem>[];
    if (rawData is List) {
      for (final item in rawData) {
        if (item is Map<String, dynamic>) {
          list.add(AnimeCalendarItem.fromJson(item));
        }
      }
    }
    final limitedList = list.take(limit).toList();
    return AnimeSearchPage(
      total: int.tryParse((decoded['total'] ?? 0).toString()) ?? 0,
      limit: int.tryParse((decoded['limit'] ?? limit).toString()) ?? limit,
      offset: int.tryParse((decoded['offset'] ?? offset).toString()) ?? offset,
      data: limitedList,
      request: body,
    );
  }

  Future<List<AnimeCalendarItem>> searchAnimeByAirDateRange({
    required DateTime startDate,
    required DateTime endDate,
    int pageSize = 50,
    int maxPages = 10,
  }) async {
    final results = <AnimeCalendarItem>[];
    final seenIds = <int>{};
    final startText = _formatDate(startDate);
    final endText = _formatDate(endDate);
    for (var page = 0; page < maxPages; page++) {
      final offset = page * pageSize;
      final pageResult = await searchSubjects(
        keyword: '',
        sort: 'heat',
        airDate: ['>=$startText', '<=$endText'],
        limit: pageSize,
        offset: offset,
      );
      final rawData = pageResult.data;
      if (rawData.isEmpty) {
        break;
      }
      var uniqueAdded = 0;
      for (final item in rawData) {
        if (item.id <= 0 || seenIds.contains(item.id)) {
          continue;
        }
        seenIds.add(item.id);
        results.add(item);
        uniqueAdded++;
      }
      if (uniqueAdded == 0) {
        break;
      }
    }
    return results;
  }

  String _formatDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class AnimeSearchPage {
  AnimeSearchPage({
    required this.total,
    required this.limit,
    required this.offset,
    required this.data,
    this.request = const {},
  });

  final int total;
  final int limit;
  final int offset;
  final List<AnimeCalendarItem> data;
  final Map<String, dynamic> request;
}

class AnimeCharacterSearchPage {
  AnimeCharacterSearchPage({
    required this.total,
    required this.limit,
    required this.offset,
    required this.data,
    this.request = const {},
  });

  final int total;
  final int limit;
  final int offset;
  final List<AnimeCharacter> data;
  final Map<String, dynamic> request;
}

class BangumiPersonSearchPage {
  BangumiPersonSearchPage({
    required this.total,
    required this.limit,
    required this.offset,
    required this.data,
    this.request = const {},
  });

  final int total;
  final int limit;
  final int offset;
  final List<BangumiPerson> data;
  final Map<String, dynamic> request;
}

class BangumiPerson {
  BangumiPerson({
    required this.id,
    required this.name,
    required this.displayName,
    required this.careers,
    required this.summary,
    required this.imageUrl,
  });

  final int id;
  final String name;
  final String displayName;
  final List<String> careers;
  final String summary;
  final String imageUrl;

  factory BangumiPerson.fromJson(Map<String, dynamic> json) {
    final id = int.tryParse((json['id'] ?? 0).toString()) ?? 0;
    final name = (json['name'] ?? '').toString().trim();
    final displayName = (json['name_cn'] ?? '').toString().trim().isNotEmpty
        ? (json['name_cn'] ?? '').toString().trim()
        : name;

    final careers = <String>[];
    final careersRaw = json['career'];
    if (careersRaw is List) {
      for (final item in careersRaw) {
        final value = item?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          careers.add(value);
        }
      }
    } else {
      final value = careersRaw?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        careers.add(value);
      }
    }

    var imageUrl = '';
    final images = json['images'];
    if (images is Map<String, dynamic>) {
      const keys = ['large', 'medium', 'small', 'grid', 'common'];
      for (final key in keys) {
        final value = images[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          imageUrl = value;
          break;
        }
      }
    }

    final summary =
        (json['short_summary'] ?? json['summary'] ?? '').toString().trim();

    return BangumiPerson(
      id: id,
      name: name,
      displayName: displayName.isNotEmpty ? displayName : name,
      careers: careers,
      summary: summary,
      imageUrl: imageUrl,
    );
  }
}

class PersonRelatedCharacter {
  PersonRelatedCharacter({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.relation,
    required this.imageUrl,
    required this.subjects,
  });

  final int id;
  final String name;
  final String nameCn;
  final String summary;
  final String relation;
  final String imageUrl;
  final List<PersonRelatedCharacterSubject> subjects;

  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  factory PersonRelatedCharacter.fromJson(Map<String, dynamic> json) {
    final characterSource = json['character'];
    final source =
        characterSource is Map<String, dynamic> ? characterSource : json;
    final imageObj = source['images'];
    final imageUrl = imageObj is Map<String, dynamic>
        ? (imageObj['medium']?.toString().trim().isNotEmpty == true
            ? imageObj['medium'].toString().trim()
            : imageObj['small']?.toString().trim() ?? '')
        : '';
    final rawSubjects = json['subjects'] ?? source['subjects'];
    final subjects = <PersonRelatedCharacterSubject>[];
    if (rawSubjects is List) {
      for (final item in rawSubjects) {
        if (item is Map<String, dynamic>) {
          final subject = PersonRelatedCharacterSubject.fromJson(item);
          if (subject.id <= 0 || subject.displayName.isEmpty) {
            continue;
          }
          subjects.add(subject);
        }
      }
    }
    if (subjects.isEmpty) {
      final flatSubject =
          PersonRelatedCharacterSubject.fromPersonCharacterJson(json);
      if (flatSubject != null) {
        subjects.add(flatSubject);
      }
    }
    final relation =
        (json['relation'] ?? json['staff'] ?? source['relation'] ?? '')
            .toString()
            .trim();
    return PersonRelatedCharacter(
      id: int.tryParse((source['id'] ?? 0).toString()) ?? 0,
      name: source['name']?.toString().trim() ?? '',
      nameCn: source['name_cn']?.toString().trim() ?? '',
      summary: source['summary']?.toString().trim() ?? '',
      relation: relation,
      imageUrl: imageUrl,
      subjects: subjects,
    );
  }
}

class PersonRelatedCharacterSubject {
  PersonRelatedCharacterSubject({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.staff,
    required this.imageUrl,
  });

  final int id;
  final String name;
  final String nameCn;
  final String staff;
  final String imageUrl;

  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  factory PersonRelatedCharacterSubject.fromJson(Map<String, dynamic> json) {
    final imageObj = json['images'];
    final imageUrl = imageObj is Map<String, dynamic>
        ? (imageObj['common']?.toString().trim().isNotEmpty == true
            ? imageObj['common'].toString().trim()
            : imageObj['medium']?.toString().trim() ?? '')
        : '';
    return PersonRelatedCharacterSubject(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      name: json['name']?.toString().trim() ?? '',
      nameCn: json['name_cn']?.toString().trim() ?? '',
      staff: (json['staff'] ?? json['relation'] ?? '').toString().trim(),
      imageUrl: imageUrl,
    );
  }

  static PersonRelatedCharacterSubject? fromPersonCharacterJson(
    Map<String, dynamic> json,
  ) {
    final id = int.tryParse((json['subject_id'] ?? 0).toString()) ?? 0;
    final name = (json['subject_name'] ?? '').toString().trim();
    final nameCn = (json['subject_name_cn'] ?? '').toString().trim();
    if (id <= 0 || (name.isEmpty && nameCn.isEmpty)) {
      return null;
    }
    return PersonRelatedCharacterSubject(
      id: id,
      name: name,
      nameCn: nameCn,
      staff: (json['staff'] ?? json['relation'] ?? '').toString().trim(),
      imageUrl: '',
    );
  }
}
