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
    _sectionsFuture = ArchiveService.fetchSections();
  }

  void _retry() {
    setState(() {
      _sectionsFuture = ArchiveService.fetchSections(
        forceRefresh: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: FutureBuilder<Map<String, String>>(
        future: _sectionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF18C7DE),
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
            children: sections.entries.map((entry) {
              return _CategoryCard(
                identifier: entry.key,
                title: entry.value,
              );
            }).toList(),
          );
        },
      ),
    );
  }
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
      final children = await _fetchChildCategories(
        widget.identifier,
      );

      if (!mounted) {
        return;
      }

      if (children.isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _SubcategoriesScreen(
              sectionTitle: widget.title,
              categories: children,
            ),
          ),
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SectionLecturesScreen(
              identifier: widget.identifier,
              sectionTitle: widget.title,
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

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

  Future<Map<String, String>> _fetchChildCategories(
    String parentUrl,
  ) async {
    final response = await http
        .get(
          Uri.parse(parentUrl),
          headers: const {
            'User-Agent': 'Mozilla/5.0',
            'Accept': 'text/html,application/xhtml+xml',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        'تعذر تحميل القسم: HTTP ${response.statusCode}',
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
      final title = _cleanHtmlText(rawTitle);

      if (url.isEmpty || title.isEmpty) {
        continue;
      }

      if (_sameUrl(url, parentUrl)) {
        continue;
      }

      final cleanedTitle = _cleanSectionTitle(title);

      if (cleanedTitle.isEmpty) {
        continue;
      }

      if (!_isUsefulTitle(cleanedTitle)) {
        continue;
      }

      result[url] = cleanedTitle;
    }

    return result;
  }

  bool _sameUrl(String first, String second) {
    String normalize(String value) {
      return value
          .trim()
          .replaceFirst(RegExp(r'/+$'), '')
          .toLowerCase();
    }

    return normalize(first) == normalize(second);
  }

  String _normalizeUrl(String url) {
    var value = url.trim().replaceAll('&amp;', '&');

    if (value.isEmpty) {
      return '';
    }

    if (value.startsWith('//')) {
      return 'https:$value';
    }

    if (value.startsWith('/')) {
      return 'https://khogaliibrahim.com$value';
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

    return 'https://khogaliibrahim.com/${value.replaceFirst(RegExp(r'^/+'), '')}';
  }

  String _cleanHtmlText(String value) {
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
        .replaceAll('&gt;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return text;
  }

  String _cleanSectionTitle(String title) {
    var result = title
        .replaceAll(RegExp(r'\s+'), ' ')
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

  bool _isUsefulTitle(String title) {
    const ignored = {
      'تحميل الكل',
      'تحميل',
      'المزيد',
      'التالي',
      'السابق',
      'الصوتيات',
    };

    return !ignored.contains(title.trim());
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
        subtitle: 'عرض الأقسام والمحاضرات',
      ),
    );
  }
}

class _SubcategoriesScreen extends StatelessWidget {
  final String sectionTitle;
  final Map<String, String> categories;

  const _SubcategoriesScreen({
    required this.sectionTitle,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.mainText,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          sectionTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.mainText,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: GridView.count(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          30,
        ),
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1.1,
        children: categories.entries.map((entry) {
          return _SubcategoryCard(
            identifier: entry.key,
            title: entry.value,
          );
        }).toList(),
      ),
    );
  }
}

class _SubcategoryCard extends StatefulWidget {
  final String identifier;
  final String title;

  const _SubcategoryCard({
    required this.identifier,
    required this.title,
  });

  @override
  State<_SubcategoryCard> createState() => _SubcategoryCardState();
}

class _SubcategoryCardState extends State<_SubcategoryCard> {
  bool _pressed = false;

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SectionLecturesScreen(
          identifier: widget.identifier,
          sectionTitle: widget.title,
        ),
      ),
    );
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
        loading: false,
        subtitle: 'عرض المحاضرات',
      ),
    );
  }
}

class _CategoryCardDesign extends StatelessWidget {
  final String title;
  final bool pressed;
  final bool loading;
  final String subtitle;

  const _CategoryCardDesign({
    required this.title,
    required this.pressed,
    required this.loading,
    required this.subtitle,
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
            child: Column(
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
                loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF18C7DE),
                        ),
                      )
                    : Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.secondaryText
                              .withOpacity(0.8),
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
            color: Color(0xFF18C7DE),
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
              color: AppColors.secondaryText
                  .withOpacity(0.85),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF18C7DE),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
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
            Icons.library_music_outlined,
            size: 52,
            color: Color(0xFF18C7DE),
          ),
          const SizedBox(height: 14),
          const Text(
            'لا توجد أقسام حاليًا',
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
              backgroundColor: const Color(0xFF18C7DE),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
