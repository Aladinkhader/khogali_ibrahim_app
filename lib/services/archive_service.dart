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

  // تم رفع الإصدار حتى لا تختلط البيانات القديمة
  // بطريقة الاستخراج السابقة مع الطريقة الجديدة.
  static const String _cacheKey = 'khogali_lectures_cache_v2';

  // Cache مستقل لمحاضرات كل قسم.
  static const String _sectionLecturesCacheKey =
      'khogali_section_lectures_cache_v2';

  static const Duration _requestTimeout = Duration(seconds: 20);

  // عدد طلبات الصفحات التي تعمل في نفس الوقت.
  static const int _parallelRequests = 6;

  // الحد الأقصى لصفحات الدروس التي نفحصها داخل القسم.
  static const int _maxLecturePagesPerSection = 80;

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

      final cleanedTitle = _cleanSectionTitle(title);

      if (cleanedTitle.isEmpty) {
        continue;
      }

      // المحاضرات لا نريدها في التطبيق.
      if (_isDeletedSection(cleanedTitle)) {
        continue;
      }

      result[url] = cleanedTitle;
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

  /// يجلب صفحات الأقسام بالتوازي على دفعات صغيرة.
  static Future<List<Lecture>> _fetchFromNetwork() async {
    final sectionsMap = await fetchSections();

    final List<Lecture> all = [];
    final List<String> errors = [];

    final entries = sectionsMap.entries.toList();

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
              final lectures = await fetchSectionLectures(
                entry.key,
                entry.value,
              );

              return _SectionFetchResult.success(
                lectures,
              );
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

  /// يجلب محاضرات قسم واحد من الموقع.
  ///
  /// الطريقة الجديدة:
  ///
  /// 1. نفحص صفحة القسم نفسها بحثًا عن ملفات الصوت المباشرة.
  /// 2. إذا لم نجدها، نستخرج روابط صفحات الدروس الموجودة داخل القسم.
  /// 3. نفتح صفحات الدروس ونبحث داخلها عن ملف الصوت.
  /// 4. نحفظ النتيجة في Cache فقط إذا وجدنا محاضرات فعلية.
  static Future<List<Lecture>> fetchSectionLectures(
    String identifier,
    String sectionTitle,
  ) async {
    final url = _normalizeUrl(identifier);

    if (url.isEmpty) {
      throw Exception('رابط القسم غير صالح.');
    }

    // المحاضرات محذوفة من التطبيق.
    if (_isDeletedSection(sectionTitle)) {
      return [];
    }

    final cached = await _readSectionLecturesCache(url);

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

  /// تحميل قسم واحد من الموقع وحفظه في Cache.
  static Future<List<Lecture>> _fetchSectionLecturesFromWebsite(
    String url,
    String sectionTitle, {
    bool saveToCache = false,
  }) async {
    final html = await _fetchHtml(url);

    final List<Lecture> lectures = [];
    final Set<String> foundUrls = {};

    // أولًا: نبحث عن ملفات الصوت الموجودة مباشرة داخل صفحة القسم.
    _extractArchiveAudioLectures(
      html: html,
      sectionTitle: sectionTitle,
      identifier: url,
      lectures: lectures,
      foundUrls: foundUrls,
    );

    // إذا كانت الملفات موجودة مباشرة فلا نحتاج لفتح صفحات إضافية.
    if (lectures.isNotEmpty) {
      _sortLectures(lectures);

      if (saveToCache) {
        await _writeSectionLecturesCache(
          url,
          lectures,
        );
      }

      return lectures;
    }

    /*
     * الصفحة لا تحتوي على ملفات الصوت مباشرة.
     *
     * نبحث عن صفحات الدروس/المواد داخل نفس الموقع.
     */
    final lectureLinks = _extractLecturePageLinks(
      html,
      sectionUrl: url,
    );

    if (lectureLinks.isEmpty) {
      return [];
    }

    /*
     * نفتح صفحات الدروس بالتوازي.
     * نستخدم دفعات صغيرة حتى لا نضغط على الموقع.
     */
    for (var start = 0;
        start < lectureLinks.length;
        start += _parallelRequests) {
      final end = (start + _parallelRequests < lectureLinks.length)
          ? start + _parallelRequests
          : lectureLinks.length;

      final batch = lectureLinks.sublist(start, end);

      final results = await Future.wait(
        batch.map(
          (lecturePage) async {
            try {
              return await _extractLecturesFromPage(
                lecturePage.url,
                sectionTitle,
                sectionUrl: url,
              );
            } catch (_) {
              return <Lecture>[];
            }
          },
        ),
      );

      for (final pageLectures in results) {
        for (final lecture in pageLectures) {
          if (foundUrls.add(lecture.audioUrl)) {
            lectures.add(lecture);
          }
        }
      }
    }

    _sortLectures(lectures);

    /*
     * مهم:
     *
     * لا نحفظ Cache فارغًا.
     *
     * إذا حدث فشل مؤقت في الإنترنت، نحاول مرة أخرى
     * في المرة القادمة بدل أن تبقى "لا توجد نتائج"
     * محفوظة إلى الأبد.
     */
    if (saveToCache && lectures.isNotEmpty) {
      await _writeSectionLecturesCache(
        url,
        lectures,
      );
    }

    return lectures;
  }

  /// يحدث Cache قسم واحد في الخلفية دون تعطيل الشاشة.
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

  /// يجلب HTML لصفحة واحدة.
  static Future<String> _fetchHtml(String url) async {
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
        'تعذر تحميل الصفحة: HTTP ${response.statusCode}',
      );
    }

    return utf8.decode(response.bodyBytes);
  }

  /// يستخرج ملفات Archive.org من صفحة HTML.
  static void _extractArchiveAudioLectures({
    required String html,
    required String sectionTitle,
    required String identifier,
    required List<Lecture> lectures,
    required Set<String> foundUrls,
  }) {
    final archiveRegex = RegExp(
      r'''(?:https?:)?\/\/(?:www\.)?archive\.org\/download\/[^"'\\s<>]+''',
      caseSensitive: false,
    );

    for (final match in archiveRegex.allMatches(html)) {
      var audioUrl = match.group(0) ?? '';

      audioUrl = audioUrl
          .replaceAll('&amp;', '&')
          .replaceAll('&#038;', '&');

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
  }

  /// يستخرج روابط صفحات الدروس الموجودة داخل صفحة القسم.
  ///
  /// لا نعتمد على نص معين مثل "التصنيفات الفرعية".
  /// بل نبحث عن روابط صفحات الصوتيات نفسها.
  static List<_LecturePageLink> _extractLecturePageLinks(
    String html, {
    required String sectionUrl,
  }) {
    final List<_LecturePageLink> result = [];
    final Set<String> foundUrls = {};

    final linkRegex = RegExp(
      r'''<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>''',
      caseSensitive: false,
    );

    for (final match in linkRegex.allMatches(html)) {
      final rawUrl = match.group(1) ?? '';
      final rawTitle = match.group(2) ?? '';

      final url = _normalizeUrl(rawUrl);

      if (url.isEmpty) {
        continue;
      }

      if (!_isSameSite(url)) {
        continue;
      }

      if (_isIgnoredPageUrl(url)) {
        continue;
      }

      final title = _cleanHtmlText(rawTitle);

      if (title.isEmpty) {
        continue;
      }

      /*
       * صفحات المواد الصوتية في الموقع عادة تكون تحت /audio/.
       *
       * نسمح أيضًا ببعض الروابط التي لا يظهر فيها /audio/
       * إذا كان عنوان الرابط واضحًا وليس رابط تنقل عام.
       */
      final uri = Uri.tryParse(url);

      if (uri == null) {
        continue;
      }

      final path = uri.path.toLowerCase();

      final looksLikeAudioPage =
          path.contains('/audio/') ||
          path.contains('/audio?') ||
          path.contains('/lesson/') ||
          path.contains('/lecture/');

      if (!looksLikeAudioPage) {
        continue;
      }

      if (!foundUrls.add(url)) {
        continue;
      }

      result.add(
        _LecturePageLink(
          url: url,
          title: title,
        ),
      );

      if (result.length >= _maxLecturePagesPerSection) {
        break;
      }
    }

    return result;
  }

  /// يفتح صفحة مادة واحدة ويستخرج منها الملفات الصوتية.
  static Future<List<Lecture>> _extractLecturesFromPage(
    String pageUrl,
    String sectionTitle, {
    required String sectionUrl,
  }) async {
    final html = await _fetchHtml(pageUrl);

    final List<Lecture> lectures = [];
    final Set<String> foundUrls = {};

    _extractArchiveAudioLectures(
      html: html,
      sectionTitle: sectionTitle,
      identifier: sectionUrl,
      lectures: lectures,
      foundUrls: foundUrls,
    );

    if (lectures.isEmpty) {
      return [];
    }

    /*
     * إذا كان اسم الملف عامًا جدًا، نحاول استخدام عنوان صفحة المادة.
     */
    final pageTitle = _extractPageTitle(html);

    if (pageTitle.isNotEmpty) {
      for (var i = 0; i < lectures.length; i++) {
        final current = lectures[i];

        if (_isGenericLectureTitle(current.title)) {
          lectures[i] = Lecture(
            title: _cleanLecturePageTitle(pageTitle),
            section: current.section,
            audioUrl: current.audioUrl,
            identifier: current.identifier,
          );
        }
      }
    }

    return lectures;
  }

  /// يستخرج عنوان الصفحة من <title>.
  static String _extractPageTitle(String html) {
    final match = RegExp(
      r'<title[^>]*>([\s\S]*?)<\/title>',
      caseSensitive: false,
    ).firstMatch(html);

    if (match == null) {
      return '';
    }

    return _cleanHtmlText(
      match.group(1) ?? '',
    );
  }

  /// ينظف عنوان صفحة الدرس.
  static String _cleanLecturePageTitle(String title) {
    var result = title.trim();

    result = result
        .replaceAll(
          RegExp(r'\s*[\-|–|—]\s*الشيخ.*$', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\s*\|\s*.*$'),
          '',
        )
        .trim();

    return result.isEmpty ? title.trim() : result;
  }

  /// هل عنوان الدرس عام جدًا؟
  static bool _isGenericLectureTitle(String title) {
    final normalized = title.trim().toLowerCase();

    if (normalized.isEmpty) {
      return true;
    }

    if (RegExp(r'^الدرس\s+\d+$').hasMatch(normalized)) {
      return true;
    }

    if (RegExp(r'^\d+$').hasMatch(normalized)) {
      return true;
    }

    return false;
  }

  /// ينشئ اسمًا نظيفًا للمحاضرة من اسم الملف الموجود في Archive.org.
  static String _buildLectureTitle(String fileName) {
    var name = fileName;

    final extensionIndex = name.lastIndexOf('.');

    if (extensionIndex > 0) {
      name = name.substring(0, extensionIndex);
    }

    try {
      name = Uri.decodeComponent(name);
    } catch (_) {}

    name = name.trim();

    final numberMatch = RegExp(
      r'^\s*(\d+)\s*$',
    ).firstMatch(name);

    if (numberMatch != null) {
      return 'الدرس ${numberMatch.group(1)}';
    }

    final arabicNumberMatch = RegExp(
      r'^\s*الدرس[\s_-]*(\d+)\s*$',
      caseSensitive: false,
    ).firstMatch(name);

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
    final normalized = _normalizeArabicDigits(title);

    final match = RegExp(r'\d+').firstMatch(normalized);

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

    result = _normalizeArabicDigits(result);

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

  /// الأقسام التي لا نريد ظهورها في التطبيق.
  static bool _isDeletedSection(String title) {
    final normalized = _normalizeTitle(title);

    return normalized == 'المحاضرات';
  }

  static String _normalizeTitle(String title) {
    return title
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        )
        .trim()
        .toLowerCase();
  }

  /// هل الرابط تابع للموقع نفسه؟
  static bool _isSameSite(String url) {
    try {
      final uri = Uri.parse(url);

      return uri.host.isEmpty ||
          uri.host.toLowerCase() == 'khogaliibrahim.com' ||
          uri.host.toLowerCase() == 'www.khogaliibrahim.com';
    } catch (_) {
      return false;
    }
  }

  /// يستبعد روابط التنقل والأقسام التي لا تمثل صفحة درس.
  static bool _isIgnoredPageUrl(String url) {
    final lower = url.toLowerCase();

    if (lower.contains('/audio-category/')) {
      return true;
    }

    if (lower.contains('/category/')) {
      return true;
    }

    if (lower.contains('/tag/')) {
      return true;
    }

    if (lower.contains('/author/')) {
      return true;
    }

    if (lower.contains('/feed')) {
      return true;
    }

    if (lower.contains('/comments')) {
      return true;
    }

    if (lower.endsWith('/الصوتيات/') ||
        lower.endsWith('/الصوتيات')) {
      return true;
    }

    return false;
  }

  /// يحول الروابط النسبية إلى روابط كاملة.
  static String _normalizeUrl(String url) {
    var value = url.trim();

    if (value.isEmpty) {
      return '';
    }

    value = value
        .replaceAll('&amp;', '&')
        .replaceAll('&#038;', '&');

    if (value.startsWith('//')) {
      return 'https:$value';
    }

    if (value.startsWith('/')) {
      return '$_siteBaseUrl$value';
    }

    if (value.startsWith('http://')) {
      return value.replaceFirst(
        'http://',
        'https://',
      );
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

    text = text
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        )
        .trim();

    return text;
  }

  static bool _isAudioUrl(String url) {
    final lower = url.toLowerCase();

    return lower.endsWith('.mp3') ||
        lower.contains('.mp3?') ||
        lower.endsWith('.m4a') ||
        lower.contains('.m4a?') ||
        lower.endsWith('.ogg') ||
        lower.contains('.ogg?') ||
        lower.endsWith('.wav') ||
        lower.contains('.wav?');
  }

  static String _extractFileName(String url) {
    try {
      final uri = Uri.parse(url);

      if (uri.pathSegments.isEmpty) {
        return '';
      }

      return Uri.decodeComponent(
        uri.pathSegments.last,
      );
    } catch (_) {
      return '';
    }
  }

  static String _normalizeArabicDigits(String value) {
    return value
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9');
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

      await prefs.setString(
        _cacheKey,
        raw,
      );
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

  /// يقرأ Cache المحاضرات الخاصة بكل قسم.
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

  /// يقرأ محاضرات قسم محدد من التخزين المحلي.
  static Future<List<Lecture>?> _readSectionLecturesCache(
    String identifier,
  ) async {
    final cache = await _readAllSectionLecturesCache();

    return cache[identifier];
  }

  /// يحفظ محاضرات قسم محدد في التخزين المحلي.
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

  /// يرجع تشكيلة من المحاضرات لواجهة الرئيسية.
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

    // تنظيف Cache الإصدار السابق أيضًا.
    await prefs.remove('khogali_lectures_cache_v1');
    await prefs.remove('khogali_lectures_cache_v1_sections');
    await prefs.remove(
      'khogali_section_lectures_cache_v1',
    );
  }
}

/// رابط صفحة درس داخل السلسلة.
class _LecturePageLink {
  final String url;
  final String title;

  const _LecturePageLink({
    required this.url,
    required this.title,
  });
}

/// نتيجة تحميل قسم واحد.
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
