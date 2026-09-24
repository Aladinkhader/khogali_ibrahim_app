import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lecture.dart';

class ArchiveService {
  static const String _siteBaseUrl = 'https://khogaliibrahim.com';

  static const String _audioPageUrl =
      'https://khogaliibrahim.com/%D8%A7%D9%84%D8%B5%D9%88%D8%AA%D9%8A%D8%A7%D8%AA/';

  static const Map<String, String> sections = {};

  static const String _cacheKey = 'khogali_lectures_cache_v1';

  static const String _sectionLecturesCacheKey =
      'khogali_section_lectures_cache_v1';

  static const Duration _requestTimeout = Duration(seconds: 20);

  static const int _parallelRequests = 6;

  // ترتيب الأقسام المطلوب ظهوره في التطبيق.
  // بقية الأقسام ستظهر بعد ذلك حسب ترتيب الموقع.
  static const List<String> _preferredSectionOrder = [
    'العقيدة الطحاوية',
    'الواسطية',
    'نخبة الفكر',
    'الرحبية',
    'القواعد المثلى',
  ];

  static Future<Map<String, String>> fetchSections({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await _readSectionsCache();

      if (cached != null && cached.isNotEmpty) {
        final orderedCached = _sortSections(cached);

        _refreshSectionsInBackground();

        return orderedCached;
      }
    }

    final fresh = await _fetchSectionsFromWebsite();

    if (fresh.isEmpty) {
      throw Exception('لم يتم العثور على الأقسام الصوتية في موقع الشيخ.');
    }

    final orderedFresh = _sortSections(fresh);

    await _writeSectionsCache(orderedFresh);

    return orderedFresh;
  }

  static Future<void> _refreshSectionsInBackground() async {
    try {
      final fresh = await _fetchSectionsFromWebsite();

      if (fresh.isNotEmpty) {
        final orderedFresh = _sortSections(fresh);

        await _writeSectionsCache(orderedFresh);
      }
    } catch (_) {}
  }

  static Future<Map<String, String>> _fetchSectionsFromWebsite() async {
    final response = await http
        .get(
          Uri.parse(_audioPageUrl),
          headers: const {
            'User-Agent': 'Mozilla/5.0',
            'Accept': 'text/html,application/xhtml+xml',
          },
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'تعذر تحميل صفحة الصوتيات: HTTP ${response.statusCode}',
      );
    }

    final html = utf8.decode(response.bodyBytes);

    final Map<String, String> result = {};

    final linkRegex = RegExp(
      r'''<a\b[^>]*href\s*=\s*["']([^"']*\/audio-category\/[^"']+)["'][^>]*>([\s\S]*?)<\/a>''',
      caseSensitive: false,
    );

    for (final match in linkRegex.allMatches(html)) {
      final rawUrl = match.group(1) ?? '';
      final rawTitle = match.group(2) ?? '';

      final url = _normalizeUrl(rawUrl);

      if (url.isEmpty) {
        continue;
      }

      final title = _cleanHtmlText(rawTitle);

      if (title.isEmpty) {
        continue;
      }

      if (!_isUsefulSectionTitle(title)) {
        continue;
      }

      result[url] = _cleanSectionTitle(title);
    }

    return result;
  }

  static Map<String, String> _sortSections(
    Map<String, String> input,
  ) {
    final ordered = <String, String>{};
    final usedKeys = <String>{};

    for (final preferredTitle in _preferredSectionOrder) {
      for (final entry in input.entries) {
        if (usedKeys.contains(entry.key)) {
          continue;
        }

        if (_sectionTitlesMatch(entry.value, preferredTitle)) {
          ordered[entry.key] = entry.value;
          usedKeys.add(entry.key);
          break;
        }
      }
    }

    for (final entry in input.entries) {
      if (!usedKeys.contains(entry.key)) {
        ordered[entry.key] = entry.value;
      }
    }

    return ordered;
  }

  static bool _sectionTitlesMatch(
    String actual,
    String preferred,
  ) {
    final normalizedActual = _normalizeSectionTitle(actual);
    final normalizedPreferred = _normalizeSectionTitle(preferred);

    return normalizedActual == normalizedPreferred;
  }

  static String _normalizeSectionTitle(String title) {
    return title
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('ـ', '')
        .trim();
  }

  static Future<List<Lecture>> fetchAllLectures({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await _readCache();

      if (cached != null && cached.isNotEmpty) {
        _refreshCacheInBackground();
        return cached;
      }
    }

    final fresh = await _fetchFromNetwork();

    if (fresh.isEmpty) {
      throw Exception('لم يتم العثور على أي محاضرات.');
    }

    await _writeCache(fresh);

    return fresh;
  }

  static Future<void> _refreshCacheInBackground() async {
    try {
      final fresh = await _fetchFromNetwork();

      if (fresh.isNotEmpty) {
        await _writeCache(fresh);
      }
    } catch (_) {}
  }

  static Future<List<Lecture>> _fetchFromNetwork() async {
    final sectionsMap = await fetchSections();

    final List<Lecture> all = [];
    final List<String> errors = [];

    final entries = sectionsMap.entries.toList();

    for (var start = 0; start < entries.length; start += _parallelRequests) {
      final end = (start + _parallelRequests < entries.length)
          ? start + _parallelRequests
          : entries.length;

      final batch = entries.sublist(start, end);

      final results = await Future.wait(
        batch.map(
          (entry) async {
            try {
              final lectures = await fetchSectionLectures(
                entry.key,
                entry.value,
              );

              return _SectionFetchResult.success(lectures);
            } catch (e) {
              return _SectionFetchResult.failure(
                entry.value,
                e.toString(),
              );
            }
          },
        ),
      );

      for (final result in results) {
        if (result.lectures != null) {
          all.addAll(result.lectures!);
        }

        if (result.error != null) {
          errors.add(result.error!);
        }
      }
    }

    if (all.isEmpty && errors.isNotEmpty) {
      throw Exception(errors.join(' | '));
    }

    return all;
  }

  static Future<List<Lecture>> fetchSectionLectures(
    String identifier,
    String sectionTitle,
  ) async {
    final url = _normalizeUrl(identifier);

    if (url.isEmpty) {
      throw Exception('رابط القسم غير صالح.');
    }

    final cached = await _readSingleSectionLecturesCache(url);

    if (cached != null && cached.isNotEmpty) {
      _refreshSectionLecturesInBackground(
        url,
        sectionTitle,
      );

      return cached;
    }

    return _fetchSectionLecturesFromWebsite(
      url,
      sectionTitle,
      saveToCache: true,
    );
  }

  static Future<List<Lecture>> _fetchSectionLecturesFromWebsite(
    String url,
    String sectionTitle, {
    bool saveToCache = false,
  }) async {
    final response = await http
        .get(
          Uri.parse(url),
          headers: const {
            'User-Agent': 'Mozilla/5.0',
            'Accept': 'text/html,application/xhtml+xml',
          },
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'تعذر تحميل قسم "$sectionTitle": HTTP ${response.statusCode}',
      );
    }

    final html = utf8.decode(response.bodyBytes);

    final List<Lecture> lectures = [];

    final archiveRegex = RegExp(
      r'''(?:https?:)?\/\/(?:www\.)?archive\.org\/download\/[^"'\s<>]+''',
      caseSensitive: false,
    );

    final Set<String> foundUrls = {};

    for (final match in archiveRegex.allMatches(html)) {
      var audioUrl = match.group(0) ?? '';

      audioUrl = audioUrl.replaceAll('&amp;', '&');

      if (audioUrl.startsWith('//')) {
        audioUrl = 'https:$audioUrl';
      }

      if (!_isAudioUrl(audioUrl)) {
        continue;
      }

      if (!foundUrls.add(audioUrl)) {
        continue;
      }

      final fileName = _extractFileName(audioUrl);

      if (fileName.isEmpty) {
        continue;
      }

      final title = _buildLectureTitle(fileName);

      lectures.add(
        Lecture(
          title: title,
          section: sectionTitle,
          audioUrl: audioUrl,
          identifier: url,
        ),
      );
    }

    _sortLectures(lectures);

    if (saveToCache && lectures.isNotEmpty) {
      await _writeSectionLecturesCache(
        url,
        lectures,
      );
    }

    return lectures;
  }

  static Future<void> _refreshSectionLecturesInBackground(
    String url,
    String sectionTitle,
  ) async {
    try {
      await _fetchSectionLecturesFromWebsite(
        url,
        sectionTitle,
        saveToCache: true,
      );
    } catch (_) {}
  }

  static String _buildLectureTitle(String fileName) {
    var name = fileName;

    final extensionIndex = name.lastIndexOf('.');

    if (extensionIndex > 0) {
      name = name.substring(0, extensionIndex);
    }

    name = Uri.decodeComponent(name).trim();

    final numberMatch = RegExp(r'^\s*(\d+)\s*$').firstMatch(name);

    if (numberMatch != null) {
      return 'الدرس ${numberMatch.group(1)}';
    }

    final arabicNumberMatch =
        RegExp(r'^\s*الدرس[\s_-]*(\d+)\s*$', caseSensitive: false)
            .firstMatch(name);

    if (arabicNumberMatch != null) {
      return 'الدرس ${arabicNumberMatch.group(1)}';
    }

    name = name
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return name.isEmpty ? fileName : name;
  }

  static void _sortLectures(List<Lecture> lectures) {
    lectures.sort((a, b) {
      final numberA = _extractEpisodeNumber(a.title);
      final numberB = _extractEpisodeNumber(b.title);

      if (numberA != null && numberB != null) {
        return numberA.compareTo(numberB);
      }

      if (numberA != null) {
        return -1;
      }

      if (numberB != null) {
        return 1;
      }

      return a.title.compareTo(b.title);
    });
  }

  static int? _extractEpisodeNumber(String title) {
    final match = RegExp(r'\d+').firstMatch(title);

    if (match == null) {
      return null;
    }

    return int.tryParse(match.group(0)!);
  }

  static String _cleanSectionTitle(String title) {
    var result = title;

    result = result
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('  ', ' ')
        .trim();

    result = result.replaceAll(
      RegExp(
        r'\s*[-–—]?\s*144[0-9]\s*هـ?\s*$',
        caseSensitive: false,
      ),
      '',
    );

    result = result.replaceAll(
      RegExp(
        r'\s*[-–—]?\s*\d{3,4}\s*هـ?\s*$',
        caseSensitive: false,
      ),
      '',
    );

    return result.trim();
  }

  static bool _isUsefulSectionTitle(String title) {
    final normalized = title.trim();

    if (normalized.isEmpty) {
      return false;
    }

    final ignoredTitles = {
      'تحميل الكل',
      'تحميل',
      'المزيد',
      'التالي',
      'السابق',
      'الصوتيات',
    };

    return !ignoredTitles.contains(normalized);
  }

  static String _normalizeUrl(String url) {
    var value = url.trim();

    if (value.isEmpty) {
      return '';
    }

    value = value.replaceAll('&amp;', '&');

    if (value.startsWith('//')) {
      return 'https:$value';
    }

    if (value.startsWith('/')) {
      return '$_siteBaseUrl$value';
    }

    if (value.startsWith('http://')) {
      return value.replaceFirst('http://', 'https://');
    }

    if (value.startsWith('https://')) {
      return value;
    }

    return '$_siteBaseUrl/${value.replaceFirst(RegExp(r'^/+'), '')}';
  }

  static String _cleanHtmlText(String value) {
    var text = value;

    text = text.replaceAll(
      RegExp(
        r'<script[\s\S]*?<\/script>',
        caseSensitive: false,
      ),
      ' ',
    );

    text = text.replaceAll(
      RegExp(
        r'<style[\s\S]*?<\/style>',
        caseSensitive: false,
      ),
      ' ',
    );

    text = text.replaceAll(
      RegExp(r'<[^>]+>'),
      ' ',
    );

    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');

    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }

  static bool _isAudioUrl(String url) {
    final lower = url.toLowerCase();

    return lower.endsWith('.mp3') ||
        lower.contains('.mp3?') ||
        lower.endsWith('.m4a') ||
        lower.contains('.m4a?') ||
        lower.endsWith('.ogg') ||
        lower.contains('.ogg?');
  }

  static String _extractFileName(String url) {
    try {
      final uri = Uri.parse(url);

      if (uri.pathSegments.isEmpty) {
        return '';
      }

      return Uri.decodeComponent(uri.pathSegments.last);
    } catch (_) {
      return '';
    }
  }

  static Future<List<Lecture>?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final raw = prefs.getString(_cacheKey);

      if (raw == null || raw.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return null;
      }

      return decoded
          .whereType<Map>()
          .map(
            (item) => Lecture(
              title: item['title']?.toString() ?? '',
              section: item['section']?.toString() ?? '',
              audioUrl: item['audioUrl']?.toString() ?? '',
              identifier: item['identifier']?.toString() ?? '',
            ),
          )
          .where(
            (lecture) =>
                lecture.title.isNotEmpty &&
                lecture.audioUrl.isNotEmpty,
          )
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(
    List<Lecture> lectures,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final raw = jsonEncode(
        lectures
            .map(
              (lecture) => {
                'title': lecture.title,
                'section': lecture.section,
                'audioUrl': lecture.audioUrl,
                'identifier': lecture.identifier,
              },
            )
            .toList(),
      );

      await prefs.setString(_cacheKey, raw);
    } catch (_) {}
  }

  static Future<Map<String, String>?> _readSectionsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final raw = prefs.getString(
        '${_cacheKey}_sections',
      );

      if (raw == null || raw.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(raw);

      if (decoded is! Map) {
        return null;
      }

      return decoded.map(
        (key, value) => MapEntry(
          key.toString(),
          value.toString(),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeSectionsCache(
    Map<String, String> sectionsMap,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        '${_cacheKey}_sections',
        jsonEncode(sectionsMap),
      );
    } catch (_) {}
  }

  static Future<Map<String, List<Lecture>>>
      _readAllSectionLecturesCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final raw = prefs.getString(
        _sectionLecturesCacheKey,
      );

      if (raw == null || raw.isEmpty) {
        return {};
      }

      final decoded = jsonDecode(raw);

      if (decoded is! Map) {
        return {};
      }

      final result = <String, List<Lecture>>{};

      for (final entry in decoded.entries) {
        final value = entry.value;

        if (value is! List) {
          continue;
        }

        final lectures = value
            .whereType<Map>()
            .map(
              (item) => Lecture(
                title: item['title']?.toString() ?? '',
                section: item['section']?.toString() ?? '',
                audioUrl: item['audioUrl']?.toString() ?? '',
                identifier: item['identifier']?.toString() ?? '',
              ),
            )
            .where(
              (lecture) =>
                  lecture.title.isNotEmpty &&
                  lecture.audioUrl.isNotEmpty,
            )
            .toList();

        if (lectures.isNotEmpty) {
          result[entry.key.toString()] = lectures;
        }
      }

      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<List<Lecture>?> _readSingleSectionLecturesCache(
    String identifier,
  ) async {
    final cache = await _readAllSectionLecturesCache();

    return cache[identifier];
  }

  static Future<void> _writeSectionLecturesCache(
    String identifier,
    List<Lecture> lectures,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final cache = await _readAllSectionLecturesCache();

      cache[identifier] = lectures;

      final encoded = <String, dynamic>{};

      for (final entry in cache.entries) {
        encoded[entry.key] = entry.value
            .map(
              (lecture) => {
                'title': lecture.title,
                'section': lecture.section,
                'audioUrl': lecture.audioUrl,
                'identifier': lecture.identifier,
              },
            )
            .toList();
      }

      await prefs.setString(
        _sectionLecturesCacheKey,
        jsonEncode(encoded),
      );
    } catch (_) {}
  }

  static Future<List<Lecture>> fetchFeaturedMix() async {
    final sectionsMap = await fetchSections();

    if (sectionsMap.isEmpty) {
      return [];
    }

    final entries = sectionsMap.entries.toList();

    final List<List<Lecture>> selectedLists = [];

    for (var start = 0;
        start < entries.length;
        start += _parallelRequests) {
      final end = (start + _parallelRequests < entries.length)
          ? start + _parallelRequests
          : entries.length;

      final batch = entries.sublist(start, end);

      final results = await Future.wait(
        batch.map(
          (entry) async {
            try {
              return await fetchSectionLectures(
                entry.key,
                entry.value,
              );
            } catch (_) {
              return <Lecture>[];
            }
          },
        ),
      );

      for (final lectures in results) {
        if (lectures.isEmpty) {
          continue;
        }

        selectedLists.add(
          lectures.take(3).toList(),
        );

        if (selectedLists.length >= 6) {
          break;
        }
      }

      if (selectedLists.length >= 6) {
        break;
      }
    }

    final List<Lecture> mix = [];

    int index = 0;
    bool addedAny = true;

    while (addedAny) {
      addedAny = false;

      for (final list in selectedLists) {
        if (index < list.length) {
          mix.add(list[index]);
          addedAny = true;
        }
      }

      index++;
    }

    return mix;
  }

  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_cacheKey);
    await prefs.remove('${_cacheKey}_sections');
    await prefs.remove(_sectionLecturesCacheKey);
  }
}

class _SectionFetchResult {
  final List<Lecture>? lectures;
  final String? error;

  const _SectionFetchResult({
    this.lectures,
    this.error,
  });

  factory _SectionFetchResult.success(
    List<Lecture> lectures,
  ) {
    return _SectionFetchResult(
      lectures: lectures,
    );
  }

  factory _SectionFetchResult.failure(
    String sectionTitle,
    String error,
  ) {
    return _SectionFetchResult(
      error: '$sectionTitle: $error',
    );
  }
}
