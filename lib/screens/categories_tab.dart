import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/app_colors.dart';
import '../services/archive_service.dart';
import '../widgets/glow_border.dart';
import 'section_lectures_screen.dart';

class CategoriesTab extends StatefulWidget {
  const CategoriesTab({super.key});

  @override
  State<CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<CategoriesTab> {
  late Future<Map<String, String>> _sectionsFuture;

  @override
  void initState() {
    super.initState();
    _sectionsFuture = _loadFlatSections();
  }

  void _retry() {
    setState(() {
      _sectionsFuture = _loadFlatSections(
        forceRefresh: true,
      );
    });
  }

  Future<Map<String, String>> _loadFlatSections({
    bool forceRefresh = false,
  }) async {
    final mainSections = await ArchiveService.fetchSections(
      forceRefresh: forceRefresh,
    );

    final Map<String, String> result = {};

    /*
     * الفكرة الأساسية:
     *
     * إذا كان القسم الرئيسي يحتوي على تصنيفات فرعية،
     * لا نظهر القسم الرئيسي نفسه.
     *
     * مثال:
     *
     * الدورات العلمية
     *       ↓
     * شرح العقيدة الطحاوية
     * شرح العقيدة الواسطية
     * شرح سلم الوصول
     *
     * تصبح الشاشة مباشرة:
     *
     * شرح العقيدة الطحاوية
     * شرح العقيدة الواسطية
     * شرح سلم الوصول
     *
     * أما القسم الذي لا يحتوي على تصنيفات فرعية،
     * مثل المحاضرات، فيبقى كما هو.
     */

    final entries = mainSections.entries.toList();

    /*
     * نبحث عن التصنيفات الفرعية لكل قسم رئيسي.
     *
     * نستخدم Future.wait حتى لا ننتظر كل قسم وحده.
     */
    final expandedResults = await Future.wait(
      entries.map(
        (entry) async {
          try {
            final children = await _fetchChildCategories(
              entry.key,
            );

            return _ExpandedSection(
              parentIdentifier: entry.key,
              parentTitle: entry.value,
              children: children,
            );
          } catch (_) {
            return _ExpandedSection(
              parentIdentifier: entry.key,
              parentTitle: entry.value,
              children: {},
            );
          }
        },
      ),
    );

    for (final section in expandedResults) {
      if (section.children.isNotEmpty) {
        /*
         * القسم لديه تصنيفات فرعية.
         *
         * نضيف التصنيفات الفرعية مباشرة للشاشة الرئيسية.
         */
        for (final child in section.children.entries) {
          final title = child.value;

          final existingKey = _findSameTitleKey(
            result,
            title,
          );

          if (existingKey != null) {
            /*
             * إذا كانت نفس السلسلة موجودة من قسم آخر،
             * نترك النسخة الموجودة.
             */
            continue;
          }

          result[child.key] = title;
        }
      } else {
        /*
         * لا توجد تصنيفات فرعية.
         *
         * نضيف القسم نفسه.
         *
         * مثال:
         *
         * المحاضرات → المحاضرات مباشرة.
         */
        final title = _cleanSectionTitle(
          section.parentTitle,
        );

        if (title.isEmpty) {
          continue;
        }

        final existingKey = _findSameTitleKey(
          result,
          title,
        );

        if (existingKey == null) {
          result[section.parentIdentifier] = title;
        }
      }
    }

    return result;
  }

  String? _findSameTitleKey(
    Map<String, String> map,
    String title,
  ) {
    final normalized = _normalizeTitleForComparison(
      title,
    );

    for (final entry in map.entries) {
      if (_normalizeTitleForComparison(
            entry.value,
          ) ==
          normalized) {
        return entry.key;
      }
    }

    return null;
  }

  String _normalizeTitleForComparison(
    String title,
  ) {
    return title
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        )
        .trim()
        .toLowerCase();
  }

  Future<Map<String, String>> _fetchChildCategories(
    String parentUrl,
  ) async {
    final response = await http
        .get(
          Uri.parse(parentUrl),
          headers: const {
            'User-Agent': 'Mozilla/5.0',
            'Accept':
                'text/html,application/xhtml+xml',
          },
        )
        .timeout(
          const Duration(seconds: 20),
        );

    if (response.statusCode != 200) {
      throw Exception(
        'تعذر تحميل القسم: HTTP ${response.statusCode}',
      );
    }

    final html = utf8.decode(
      response.bodyBytes,
    );

    /*
     * نبحث عن "التصنيفات الفرعية".
     *
     * هذا يمنع التقاط الأقسام العامة الموجودة
     * في القائمة الرئيسية للموقع.
     */
    final markerRegex = RegExp(
      r'التصنيفات\s*الفرعية',
      caseSensitive: false,
    );

    final markerMatch = markerRegex.firstMatch(
      html,
    );

    if (markerMatch == null) {
      return {};
    }

    var subcategoryHtml = html.substring(
      markerMatch.end,
    );

    /*
     * نوقف البحث قبل الوصول إلى أجزاء أخرى
     * من الصفحة.
     */
    final stopMarkers = [
      'الأقسام ذات الصلة',
      'المحاضرات ذات الصلة',
      'التعليقات',
      'اترك تعليق',
      '<footer',
      'site-footer',
    ];

    for (final marker in stopMarkers) {
      final index = subcategoryHtml.indexOf(
        marker,
      );

      if (index > 0) {
        subcategoryHtml =
            subcategoryHtml.substring(
          0,
          index,
        );
      }
    }

    final linkRegex = RegExp(
      r'''<a\b[^>]*href\s*=\s*["']([^"']*\/audio-category\/[^"']+)["'][^>]*>([\s\S]*?)<\/a>''',
      caseSensitive: false,
    );

    /*
     * المفتاح هنا هو اسم السلسلة بعد تنظيفه.
     *
     * لذلك:
     *
     * شرح العقيدة الواسطية 1440
     * شرح العقيدة الواسطية 1446
     *
     * يعتبران نفس السلسلة.
     *
     * ونختار السنة الأعلى.
     */
    final Map<String, _CategoryCandidate>
        candidates = {};

    for (final match
        in linkRegex.allMatches(
      subcategoryHtml,
    )) {
      final rawUrl =
          match.group(1) ?? '';

      final rawTitle =
          match.group(2) ?? '';

      final url = _normalizeUrl(
        rawUrl,
      );

      final originalTitle =
          _cleanHtmlText(
        rawTitle,
      );

      if (url.isEmpty ||
          originalTitle.isEmpty) {
        continue;
      }

      if (_sameUrl(
        url,
        parentUrl,
      )) {
        continue;
      }

      final cleanedTitle =
          _cleanSectionTitle(
        originalTitle,
      );

      if (cleanedTitle.isEmpty) {
        continue;
      }

      if (!_isUsefulTitle(
        cleanedTitle,
      )) {
        continue;
      }

      final year =
          _extractHijriYear(
        originalTitle,
      );

      final key =
          _normalizeTitleForComparison(
        cleanedTitle,
      );

      final candidate =
          _CategoryCandidate(
        url: url,
        title: cleanedTitle,
        year: year,
      );

      final old =
          candidates[key];

      if (old == null) {
        candidates[key] =
            candidate;
      } else {
        /*
         * إذا كانت النسخة الجديدة تحمل
         * سنة أعلى، نستخدمها.
         *
         * 1446 > 1440
         */
        if (candidate.year >
            old.year) {
          candidates[key] =
              candidate;
        }
      }
    }

    final Map<String, String>
        result = {};

    for (final candidate
        in candidates.values) {
      result[candidate.url] =
          candidate.title;
    }

    return result;
  }

  int _extractHijriYear(
    String title,
  ) {
    final normalized =
        _normalizeArabicDigits(
      title,
    );

    final matches =
        RegExp(
      r'(?<!\d)(1[34]\d{2})(?!\d)',
    ).allMatches(
      normalized,
    );

    int highest = 0;

    for (final match
        in matches) {
      final year =
          int.tryParse(
        match.group(1) ?? '',
      );

      if (year != null &&
          year > highest) {
        highest = year;
      }
    }

    return highest;
  }

  String _normalizeArabicDigits(
    String value,
  ) {
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

  bool _sameUrl(
    String first,
    String second,
  ) {
    String normalize(
      String value,
    ) {
      return value
          .trim()
          .replaceFirst(
            RegExp(r'/+$'),
            '',
          )
          .toLowerCase();
    }

    return normalize(first) ==
        normalize(second);
  }

  String _normalizeUrl(
    String url,
  ) {
    var value = url
        .trim()
        .replaceAll(
          '&amp;',
          '&',
        );

    if (value.isEmpty) {
      return '';
    }

    if (value.startsWith('//')) {
      return 'https:$value';
    }

    if (value.startsWith('/')) {
      return 'https://khogaliibrahim.com$value';
    }

    if (value.startsWith(
      'http://',
    )) {
      return value.replaceFirst(
        'http://',
        'https://',
      );
    }

    if (value.startsWith(
      'https://',
    )) {
      return value;
    }

    return 'https://khogaliibrahim.com/${value.replaceFirst(RegExp(r'^/+'), '')}';
  }

  String _cleanHtmlText(
    String value,
  ) {
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
        .replaceAll(
          '&nbsp;',
          ' ',
        )
        .replaceAll(
          '&amp;',
          '&',
        )
        .replaceAll(
          '&quot;',
          '"',
        )
        .replaceAll(
          '&#039;',
          "'",
        )
        .replaceAll(
          '&#39;',
          "'",
        )
        .replaceAll(
          '&lt;',
          '<',
        )
        .replaceAll(
          '&gt;',
          ' ',
        )
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        )
        .trim();

    return text;
  }

  String _cleanSectionTitle(
    String title,
  ) {
    var result = title
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        )
        .trim();

    /*
     * توحيد الأرقام العربية قبل إزالة السنوات.
     */
    result =
        _normalizeArabicDigits(
      result,
    );

    /*
     * إزالة السنة الهجرية من آخر الاسم.
     *
     * مثال:
     *
     * شرح العقيدة الواسطية 1446 هـ
     *
     * تصبح:
     *
     * شرح العقيدة الواسطية
     */
    result = result.replaceAll(
      RegExp(
        r'\s*[-–—]?\s*(1[34]\d{2})\s*هـ?\s*$',
        caseSensitive: false,
      ),
      '',
    );

    /*
     * إزالة الأشهر الهجرية.
     *
     * مثال:
     *
     * شرح الرحبية محرم
     * شرح العقيدة الطحاوية صفر
     *
     * تصبح:
     *
     * شرح الرحبية
     * شرح العقيدة الطحاوية
     */
    const months = [
      'محرم',
      'صفر',
      'ربيع الأول',
      'ربيع الاول',
      'ربيع الآخر',
      'ربيع الاخر',
      'جمادى الأولى',
      'جمادى الاولى',
      'جمادى الآخر',
      'جمادى الاخر',
      'رجب',
      'شعبان',
      'رمضان',
      'شوال',
      'ذو القعدة',
      'ذو الحجة',
    ];

    for (final month
        in months) {
      result =
          result.replaceAll(
        RegExp(
          r'\s+' +
              RegExp.escape(
                month,
              ) +
              r'\s*$',
          caseSensitive: false,
        ),
        '',
      );
    }

    /*
     * بعد إزالة الشهر قد تبقى السنة.
     */
    result = result.replaceAll(
      RegExp(
        r'\s*[-–—]?\s*(1[34]\d{2})\s*هـ?\s*$',
        caseSensitive: false,
      ),
      '',
    );

    return result.trim();
  }

  bool _isUsefulTitle(
    String title,
  ) {
    const ignored = {
      'تحميل الكل',
      'تحميل',
      'المزيد',
      'التالي',
      'السابق',
      'الصوتيات',
      'التصنيفات',
      'التصنيفات الفرعية',
      'المحاضرات',
      'الدورات العلمية',
      'الدروس العلمية',
      'الخطب المنبرية',
      'مسائل علمية',
      'الردود والتعقيبات',
    };

    return !ignored.contains(
      title.trim(),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16,
      ),
      child: FutureBuilder<
          Map<String, String>>(
        future: _sectionsFuture,
        builder:
            (context, snapshot) {
          if (snapshot
                  .connectionState ==
              ConnectionState
                  .waiting) {
            return const Center(
              child:
                  CircularProgressIndicator(
                color:
                    Color(0xFF18C7DE),
              ),
            );
          }

          if (snapshot.hasError) {
            return _ErrorState(
              onRetry: _retry,
            );
          }

          final sections =
              snapshot.data ?? {};

          if (sections.isEmpty) {
            return _EmptyState(
              onRetry: _retry,
            );
          }

          return GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.1,
            children:
                sections.entries
                    .map(
              (entry) {
                return _CategoryCard(
                  identifier:
                      entry.key,
                  title:
                      entry.value,
                );
              },
            ).toList(),
          );
        },
      ),
    );
  }
}

class _ExpandedSection {
  final String parentIdentifier;
  final String parentTitle;
  final Map<String, String> children;

  const _ExpandedSection({
    required this.parentIdentifier,
    required this.parentTitle,
    required this.children,
  });
}

class _CategoryCandidate {
  final String url;
  final String title;
  final int year;

  const _CategoryCandidate({
    required this.url,
    required this.title,
    required this.year,
  });
}

class _CategoryCard
    extends StatefulWidget {
  final String identifier;
  final String title;

  const _CategoryCard({
    required this.identifier,
    required this.title,
  });

  @override
  State<_CategoryCard>
      createState() =>
          _CategoryCardState();
}

class _CategoryCardState
    extends State<_CategoryCard> {
  bool _pressed = false;
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) {
      return;
    }

    setState(() {
      _opening = true;
    });

    try {
      await Navigator.of(
        context,
      ).push(
        MaterialPageRoute(
          builder: (_) =>
              SectionLecturesScreen(
            identifier:
                widget.identifier,
            sectionTitle:
                widget.title,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
        });
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() {
          _pressed = true;
        });
      },
      onTapUp: (_) {
        setState(() {
          _pressed = false;
        });
      },
      onTapCancel: () {
        setState(() {
          _pressed = false;
        });
      },
      onTap: _open,
      child:
          _CategoryCardDesign(
        title: widget.title,
        pressed: _pressed,
        loading: _opening,
      ),
    );
  }
}

class _CategoryCardDesign
    extends StatelessWidget {
  final String title;
  final bool pressed;
  final bool loading;

  const _CategoryCardDesign({
    required this.title,
    required this.pressed,
    required this.loading,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return AnimatedGlowBorder(
      borderRadius:
          BorderRadius.circular(
        20,
      ),
      child: AnimatedScale(
        scale:
            pressed ? 1.02 : 1.0,
        duration:
            const Duration(
          milliseconds: 150,
        ),
        curve:
            Curves.easeOut,
        child:
            AnimatedContainer(
          duration:
              const Duration(
            milliseconds: 150,
          ),
          transform:
              Matrix4.translationValues(
            0,
            pressed ? -4 : 0,
            0,
          ),
          padding:
              const EdgeInsets.all(
            16,
          ),
          decoration:
              BoxDecoration(
            gradient:
                AppColors
                    .categoryCardGradient,
            boxShadow:
                pressed
                    ? [
                        BoxShadow(
                          color: Colors
                              .black
                              .withOpacity(
                            0.4,
                          ),
                          blurRadius:
                              22,
                          offset:
                              const Offset(
                            0,
                            12,
                          ),
                        ),
                        BoxShadow(
                          color: AppColors
                              .primaryTeal
                              .withOpacity(
                            0.3,
                          ),
                          blurRadius:
                              18,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors
                              .black
                              .withOpacity(
                            0.2,
                          ),
                          blurRadius:
                              10,
                          offset:
                              const Offset(
                            0,
                            4,
                          ),
                        ),
                      ],
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                      color:
                          Color(
                        0xFF18C7DE,
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize:
                        MainAxisSize
                            .min,
                    children: [
                      Text(
                        title,
                        textAlign:
                            TextAlign
                                .center,
                        style:
                            const TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight
                                  .w800,
                          color:
                              AppColors
                                  .mainText,
                        ),
                      ),
                      const SizedBox(
                        height: 10,
                      ),
                      Text(
                        'عرض المحاضرات',
                        textAlign:
                            TextAlign
                                .center,
                        style:
                            TextStyle(
                          fontSize: 14,
                          color: AppColors
                              .secondaryText
                              .withOpacity(
                            0.8,
                          ),
                          fontWeight:
                              FontWeight
                                  .w500,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState
    extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({
    required this.onRetry,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Center(
      child: Column(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          const Icon(
            Icons
                .cloud_off_rounded,
            size: 52,
            color:
                Color(0xFF18C7DE),
          ),
          const SizedBox(
            height: 14,
          ),
          const Text(
            'تعذر تحميل الأقسام',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.w800,
              color: AppColors
                  .mainText,
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          Text(
            'تحقق من اتصال الإنترنت ثم حاول مرة أخرى',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              fontSize: 14,
              color: AppColors
                  .secondaryText
                  .withOpacity(
                0.85,
              ),
            ),
          ),
          const SizedBox(
            height: 18,
          ),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(
              Icons
                  .refresh_rounded,
            ),
            label:
                const Text(
              'إعادة المحاولة',
            ),
            style:
                ElevatedButton.styleFrom(
              backgroundColor:
                  const Color(
                0xFF18C7DE,
              ),
              foregroundColor:
                  Colors.white,
              padding:
                  const EdgeInsets
                      .symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape:
                  RoundedRectangleBorder(
                borderRadius:
                    BorderRadius
                        .circular(
                  12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState
    extends StatelessWidget {
  final VoidCallback onRetry;

  const _EmptyState({
    required this.onRetry,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Center(
      child: Column(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          const Icon(
            Icons
                .folder_off_rounded,
            size: 52,
            color:
                Color(0xFF18C7DE),
          ),
          const SizedBox(
            height: 14,
          ),
          const Text(
            'لا توجد أقسام',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.w800,
              color: AppColors
                  .mainText,
            ),
          ),
          const SizedBox(
            height: 18,
          ),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(
              Icons
                  .refresh_rounded,
            ),
            label:
                const Text(
              'إعادة المحاولة',
            ),
            style:
                ElevatedButton.styleFrom(
              backgroundColor:
                  const Color(
                0xFF18C7DE,
              ),
              foregroundColor:
                  Colors.white,
              padding:
                  const EdgeInsets
                      .symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape:
                  RoundedRectangleBorder(
                borderRadius:
                    BorderRadius
                        .circular(
                  12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
