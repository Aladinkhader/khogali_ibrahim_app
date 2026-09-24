import 'package:flutter/material.dart';

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

  static const List<String> _preferredOrder = [
    'العقيدة الطحاوية',
    'الواسطية',
    'نخبة الفكر',
    'الرحبية',
    'القواعد المثلى',
  ];

  @override
  void initState() {
    super.initState();
    _sectionsFuture = _loadSections();
  }

  void _retry() {
    setState(() {
      _sectionsFuture = _loadSections(
        forceRefresh: true,
      );
    });
  }

  Future<Map<String, String>> _loadSections({
    bool forceRefresh = false,
  }) async {
    final sections = await ArchiveService.fetchSections(
      forceRefresh: forceRefresh,
    );

    final Map<String, String> cleaned = {};

    for (final entry in sections.entries) {
      final title = _cleanSectionTitle(entry.value);

      if (title.isEmpty) {
        continue;
      }

      if (_normalizeTitle(title) == 'المحاضرات') {
        continue;
      }

      final existingKey = _findSameTitleKey(
        cleaned,
        title,
      );

      if (existingKey != null) {
        continue;
      }

      cleaned[entry.key] = title;
    }

    if (cleaned.isEmpty) {
      return cleaned;
    }

    final entries = cleaned.entries.toList();

    final results = await Future.wait(
      entries.map(
        (entry) async {
          try {
            final lectures = await ArchiveService.fetchSectionLectures(
              entry.key,
              entry.value,
            );

            return _SectionStatus(
              identifier: entry.key,
              title: entry.value,
              hasLectures: lectures.isNotEmpty,
            );
          } catch (_) {
            return _SectionStatus(
              identifier: entry.key,
              title: entry.value,
              hasLectures: false,
            );
          }
        },
      ),
    );

    final withLectures = results
        .where((item) => item.hasLectures)
        .toList();

    final withoutLectures = results
        .where((item) => !item.hasLectures)
        .toList();

    withLectures.sort(_compareSections);
    withoutLectures.sort(_compareSections);

    final Map<String, String> ordered = {};

    for (final item in withLectures) {
      ordered[item.identifier] = item.title;
    }

    for (final item in withoutLectures) {
      ordered[item.identifier] = item.title;
    }

    return ordered;
  }

  int _compareSections(
    _SectionStatus a,
    _SectionStatus b,
  ) {
    final indexA = _preferredIndex(a.title);
    final indexB = _preferredIndex(b.title);

    if (indexA != indexB) {
      return indexA.compareTo(indexB);
    }

    return 0;
  }

  int _preferredIndex(String title) {
    final normalized = _normalizeTitle(title);

    for (var i = 0; i < _preferredOrder.length; i++) {
      if (_normalizeTitle(_preferredOrder[i]) == normalized) {
        return i;
      }
    }

    return _preferredOrder.length;
  }

  String? _findSameTitleKey(
    Map<String, String> map,
    String title,
  ) {
    final normalized = _normalizeTitle(title);

    for (final entry in map.entries) {
      if (_normalizeTitle(entry.value) == normalized) {
        return entry.key;
      }
    }

    return null;
  }

  String _normalizeTitle(String title) {
    return title
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('ـ', '')
        .trim()
        .toLowerCase();
  }

  String _cleanSectionTitle(String title) {
    var result = title
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (result.isEmpty) {
      return '';
    }

    result = _normalizeArabicDigits(result);

    result = result.replaceAll(
      RegExp(
        r'\s*[-–—]?\s*(1[34]\d{2})\s*هـ?\s*$',
        caseSensitive: false,
      ),
      '',
    );

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

    for (final month in months) {
      result = result.replaceAll(
        RegExp(
          r'\s+' + RegExp.escape(month) + r'\s*$',
          caseSensitive: false,
        ),
        '',
      );
    }

    result = result.replaceAll(
      RegExp(
        r'\s*[-–—]?\s*(1[34]\d{2})\s*هـ?\s*$',
        caseSensitive: false,
      ),
      '',
    );

    return result.trim();
  }

  String _normalizeArabicDigits(String value) {
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16,
      ),
      child: FutureBuilder<Map<String, String>>(
        future: _sectionsFuture,
        builder: (
          context,
          snapshot,
        ) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: AppColors.primaryTeal,
              ),
            );
          }

          if (snapshot.hasError) {
            return _ErrorState(
              onRetry: _retry,
            );
          }

          final sections = snapshot.data ?? {};

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
            children: sections.entries.map(
              (entry) {
                return _CategoryCard(
                  identifier: entry.key,
                  title: entry.value,
                );
              },
            ).toList(),
          );
        },
      ),
    );
  }
}

class _SectionStatus {
  final String identifier;
  final String title;
  final bool hasLectures;

  const _SectionStatus({
    required this.identifier,
    required this.title,
    required this.hasLectures,
  });
}

class _CategoryCard extends StatefulWidget {
  final String identifier;
  final String title;

  const _CategoryCard({
    required this.identifier,
    required this.title,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
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
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SectionLecturesScreen(
            identifier: widget.identifier,
            sectionTitle: widget.title,
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
  Widget build(BuildContext context) {
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
      child: _CategoryCardDesign(
        title: widget.title,
        pressed: _pressed,
        loading: _opening,
      ),
    );
  }
}

class _CategoryCardDesign extends StatelessWidget {
  final String title;
  final bool pressed;
  final bool loading;

  const _CategoryCardDesign({
    required this.title,
    required this.pressed,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedGlowBorder(
      borderRadius: BorderRadius.circular(20),
      child: AnimatedScale(
        scale: pressed ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.translationValues(
            0,
            pressed ? -4 : 0,
            0,
          ),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppColors.categoryCardGradient,
            boxShadow: pressed
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 22,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: AppColors.primaryTeal.withOpacity(0.3),
                      blurRadius: 18,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryTeal,
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.mainText,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'عرض المحاضرات',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.secondaryText.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
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

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 52,
            color: AppColors.primaryTeal,
          ),
          const SizedBox(height: 14),
          const Text(
            'تعذر تحميل الأقسام',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.mainText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'تحقق من اتصال الإنترنت ثم حاول مرة أخرى',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.secondaryText.withOpacity(0.85),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryTeal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRetry;

  const _EmptyState({
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.folder_off_rounded,
            size: 52,
            color: AppColors.primaryTeal,
          ),
          const SizedBox(height: 14),
          const Text(
            'لا توجد أقسام',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.mainText,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryTeal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
