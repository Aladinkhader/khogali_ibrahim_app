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
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SectionLecturesScreen(
              identifier: widget.identifier,
              sectionTitle: widget.title,
            ),
          ),
        );
      },
      child: AnimatedGlowBorder(
        borderRadius: BorderRadius.circular(20),
        child: AnimatedScale(
          scale: _pressed ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: Matrix4.translationValues(
              0,
              _pressed ? -4 : 0,
              0,
            ),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppColors.categoryCardGradient,
              boxShadow: _pressed
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
                    widget.title,
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
              color: AppColors.secondaryText.withOpacity(0.85),
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
