import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lecture.dart';

class ArchiveService {
  static const String _siteBaseUrl = 'https://khogaliibrahim.com';

  static const String _audioPageUrl =
      'https://khogaliibrahim.com/%D8%A7%D9%84%D8%B5%D9%88%D8%AA%D9%8A%D8%A7%D8%AA/';

  // سيتم استخدام هذا المفتاح لاحقًا من شاشة الأقسام.
  // حاليًا نحتفظ به للتوافق مع الملفات القديمة.
  static const Map<String, String> sections = {};

  // إصدار جديد حتى لا تختلط بيانات الشيخ السابق
  // مع بيانات الشيخ أبي الحسن خوجلي إبراهيم.
  static const String _cacheKey = 'khogali_lectures_cache_v1';

  static const Duration _requestTimeout = Duration(seconds: 20);

  /// يجلب أقسام الصوتيات من الموقع الرسمي.
  ///
  /// المفتاح = رابط صفحة القسم
  /// القيمة = اسم القسم
  static Future<Map<String, String>> fetchSections({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await _readSectionsCache();

      if (cached != null && cached.isNotEmpty) {
        _refreshSectionsInBackground();
        return cached;
      }
    }

    final fresh = await _fetchSectionsFromWebsite();

    if (fresh.isEmpty) {
      throw Exception('لم يتم العثور على الأقسام الصوتية في موقع الشيخ.');
    }

    await _writeSectionsCache(fresh);

    return fresh;
  }

  static Future<void> _refreshSectionsInBackground() async {
    try {
      final fresh = await _fetchSectionsFromWebsite();

      if (fresh.isNotEmpty) {
        await _writeSectionsCache(fresh);
      }
    } catch (_) {}
  }

  /// يقرأ صفحة الصوتيات ويستخرج روابط صفحات السلاسل الصوتية.
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
      throw Exception('تعذر تحميل صفحة الصوتيات: HTTP ${response.statusCode}');
    }

    final html = utf8.decode(response.bodyBytes);

    final Map<String, String> result = {};

    // نبحث عن جميع روابط audio-category في الصفحة.
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

  /// يجلب جميع المحاضرات الموجودة في جميع الأقسام.
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

    for (final entry in sectionsMap.entries) {
      try {
        final lectures = await fetchSectionLectures(
          entry.key,
          entry.value,
        );

        all.addAll(lectures);
      } catch (e) {
        errors.add('${entry.value}: $e');
      }
    }

    if (all.isEmpty && errors.isNotEmpty) {
      throw Exception(errors.join(' | '));
    }

    return all;
  }

  /// يجلب محاضرات قسم واحد من صفحة القسم في موقع الشيخ.
  ///
  /// identifier هنا هو رابط صفحة القسم نفسه.
  static Future<List<Lecture>> fetchSectionLectures(
    String identifier,
    String sectionTitle,
  ) async {
    final url = _normalizeUrl(identifier);

    if (url.isEmpty) {
      throw Exception('رابط القسم غير صالح.');
    }

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

    // الموقع يضع روابط التحميل الفعلية للصوتيات على Archive.org.
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
          identifier: identifier,
        ),
      );
    }

    _sortLectures(lectures);

    return lectures;
  }

  /// ينشئ اسمًا نظيفًا للمحاضرة من اسم الملف الموجود في Archive.org.
  ///
  /// أمثلة:
  /// 1.mp3      -> الدرس 1
  /// 2.mp3      -> الدرس 2
  /// 10.mp3     -> الدرس 10
  /// lecture.mp3 -> lecture
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

  /// ترتيب الدروس رقميًا.
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

  /// ينظف اسم القسم القادم من HTML.
  static String _cleanSectionTitle(String title) {
    var result = title;

    result = result
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('  ', ' ')
        .trim();

    // إزالة السنة الهجرية من نهاية الاسم مع الإبقاء على اسم السلسلة نظيفًا.
    result = result.replaceAll(
      RegExp(r'\s*[-–—]?\s*144[0-9]\s*هـ?\s*$', caseSensitive: false),
      '',
    );

    result = result.replaceAll(
      RegExp(r'\s*[-–—]?\s*\d{3,4}\s*هـ?\s*$', caseSensitive: false),
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

  /// يحول الروابط النسبية إلى روابط كاملة.
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
      RegExp(r'<script[\s\S]*?<\/script>', caseSensitive: false),
      ' ',
    );

    text = text.replaceAll(
      RegExp(r'<style[\s\S]*?<\/style>', caseSensitive: false),
      ' ',
    );

    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');

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
                lecture.title.isNotEmpty && lecture.audioUrl.isNotEmpty,
          )
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(List<Lecture> lectures) async {
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

      final raw = prefs.getString('${_cacheKey}_sections');

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

  /// يرجع تشكيلة من المحاضرات لواجهة الرئيسية.
  ///
  /// يتم اختيار عدد محدود من أول الدروس من الأقسام المتاحة
  /// ثم خلطها بالتناوب.
  static Future<List<Lecture>> fetchFeaturedMix() async {
    final all = await fetchAllLectures();

    if (all.isEmpty) {
      return [];
    }

    final Map<String, List<Lecture>> bySection = {};

    for (final lecture in all) {
      bySection.putIfAbsent(lecture.section, () => []).add(lecture);
    }

    final List<List<Lecture>> selectedLists = [];

    for (final entry in bySection.entries) {
      final list = entry.value;

      if (list.isEmpty) {
        continue;
      }

      selectedLists.add(list.take(3).toList());

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
  }
}
