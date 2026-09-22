import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../models/lecture.dart';
import '../services/archive_service.dart';
import '../services/audio_player_service.dart';
import '../services/favorites_service.dart';
import '../services/downloads_service.dart';
import '../services/share_service.dart';
import '../widgets/shimmer_lecture_card.dart';
import '../widgets/pulsing_border.dart';
import '../widgets/glow_border.dart';
import 'full_player.dart';

class HomeTab extends StatefulWidget {
  final VoidCallback onNavigateToCategories;

  const HomeTab({
    super.key,
    required this.onNavigateToCategories,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  static const String _featuredCacheKey =
      'khogali_featured_lectures_cache_v1';

  List<Lecture>? _lectures;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
      _error = false;
    });

    /*
     * أولًا:
     * نبحث عن المختارات المحفوظة محليًا.
     *
     * إذا كانت موجودة:
     * نعرضها مباشرة ولا نطلب الموقع.
     */
    final cached = await _readFeaturedCache();

    if (cached != null && cached.isNotEmpty) {
      if (!mounted) {
        return;
      }

      setState(() {
        _lectures = cached;
        _loading = false;
        _error = false;
      });

      return;
    }

    /*
     * لا توجد نسخة محفوظة.
     *
     * إذن هذه أول مرة فقط:
     * نجلب المختارات من الموقع.
     */
    try {
      final selected =
          await _loadFeaturedFromNetwork();

      if (selected.isEmpty) {
        throw Exception(
          'لا توجد محاضرات مختارة.',
        );
      }

      /*
       * نحفظ النسخة بعد نجاح التحميل.
       */
      await _writeFeaturedCache(
        selected,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _lectures = selected;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _lectures = null;
        _error = true;
        _loading = false;
      });
    }
  }

  /*
   * التحميل الأول فقط من الموقع.
   */
  Future<List<Lecture>> _loadFeaturedFromNetwork() async {
    /*
     * لا نستورد مكتبة المحاضرات كاملة من أجل الرئيسية.
     *
     * نجلب الأقسام فقط، ثم نأخذ عددًا محدودًا
     * من الأقسام ونحمل صفحاتها بالتوازي.
     */
    final sections =
        await ArchiveService.fetchSections();

    if (sections.isEmpty) {
      throw Exception(
        'لا توجد أقسام صوتية.',
      );
    }

    final entries =
        sections.entries.toList();

    const int batchSize = 6;
    const int wantedSections = 6;
    const int lecturesPerSection = 3;

    final List<Lecture> selected = [];

    for (
      var start = 0;
      start < entries.length &&
          selected.length <
              wantedSections *
                  lecturesPerSection;
      start += batchSize
    ) {
      final end =
          (start + batchSize <
                  entries.length)
              ? start + batchSize
              : entries.length;

      final batch =
          entries.sublist(
        start,
        end,
      );

      final results =
          await Future.wait(
        batch.map(
          (entry) async {
            try {
              return await ArchiveService
                  .fetchSectionLectures(
                entry.key,
                entry.value,
              );
            } catch (_) {
              return <Lecture>[];
            }
          },
        ),
      );

      for (final lectures
          in results) {
        if (lectures.isEmpty) {
          continue;
        }

        selected.addAll(
          lectures.take(
            lecturesPerSection,
          ),
        );

        if (selected.length >=
            wantedSections *
                lecturesPerSection) {
          break;
        }
      }
    }

    return selected;
  }

  /*
   * قراءة المختارات من التخزين المحلي.
   */
  Future<List<Lecture>?> _readFeaturedCache() async {
    try {
      final prefs =
          await SharedPreferences
              .getInstance();

      final raw =
          prefs.getString(
        _featuredCacheKey,
      );

      if (raw == null ||
          raw.isEmpty) {
        return null;
      }

      final decoded =
          jsonDecode(raw);

      if (decoded is! List) {
        return null;
      }

      final lectures = decoded
          .whereType<Map>()
          .map(
            (item) => Lecture(
              title:
                  item['title']
                          ?.toString() ??
                      '',
              section:
                  item['section']
                          ?.toString() ??
                      '',
              audioUrl:
                  item['audioUrl']
                          ?.toString() ??
                      '',
              identifier:
                  item['identifier']
                          ?.toString() ??
                      '',
            ),
          )
          .where(
            (lecture) =>
                lecture.title
                    .isNotEmpty &&
                lecture.audioUrl
                    .isNotEmpty,
          )
          .toList();

      return lectures.isEmpty
          ? null
          : lectures;
    } catch (_) {
      return null;
    }
  }

  /*
   * حفظ المختارات في التخزين المحلي.
   */
  Future<void> _writeFeaturedCache(
    List<Lecture> lectures,
  ) async {
    try {
      final prefs =
          await SharedPreferences
              .getInstance();

      final raw = jsonEncode(
        lectures
            .map(
              (lecture) => {
                'title':
                    lecture.title,
                'section':
                    lecture.section,
                'audioUrl':
                    lecture.audioUrl,
                'identifier':
                    lecture.identifier,
              },
            )
            .toList(),
      );

      await prefs.setString(
        _featuredCacheKey,
        raw,
      );
    } catch (_) {}
  }

  void _openLecture(
    Lecture lecture,
    List<Lecture> queue,
  ) {
    AudioPlayerService.instance
        .playLecture(
      lecture,
      queue: queue,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const FullPlayerScreen(),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        100,
      ),
      children: [
        _WelcomeCard(
          onBrowseTap:
              widget.onNavigateToCategories,
        ),
        const SizedBox(
          height: 28,
        ),
        Text(
          'مختارات من المحاضرات',
          style: TextStyle(
            fontSize: 16,
            fontWeight:
                FontWeight.bold,
            color:
                AppColors.lightText,
          ),
        ),
        const SizedBox(
          height: 14,
        ),
        _buildContent(),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const ShimmerLectureList(
        count: 4,
      );
    }

    if (_error ||
        _lectures == null ||
        _lectures!.isEmpty) {
      return Container(
        padding:
            const EdgeInsets.symmetric(
          vertical: 24,
        ),
        child: Column(
          children: [
            Icon(
              Icons.wifi_off_rounded,
              color: AppColors
                  .secondaryText
                  .withOpacity(0.6),
              size: 32,
            ),
            const SizedBox(
              height: 10,
            ),
            Text(
              'اتصل بالإنترنت لعرض المحاضرات',
              style: TextStyle(
                color: AppColors
                    .secondaryText,
                fontSize: 12,
              ),
            ),
            const SizedBox(
              height: 12,
            ),
            TextButton(
              onPressed: _load,
              child:
                  const Text(
                'إعادة المحاولة',
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _lectures!
          .map(
            (lecture) => Padding(
              padding:
                  const EdgeInsets.only(
                bottom: 14,
              ),
              child: _LectureCard(
                lecture: lecture,
                onTap: () =>
                    _openLecture(
                  lecture,
                  _lectures!,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _WelcomeCard
    extends StatefulWidget {
  final VoidCallback onBrowseTap;

  const _WelcomeCard({
    required this.onBrowseTap,
  });

  @override
  State<_WelcomeCard> createState() =>
      _WelcomeCardState();
}

class _WelcomeCardState
    extends State<_WelcomeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController
      _autoPulseController;

  @override
  void initState() {
    super.initState();

    _autoPulseController =
        AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 1400,
      ),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _autoPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedGlowBorder(
      borderRadius:
          BorderRadius.circular(20),
      child: AnimatedBuilder(
        animation:
            _autoPulseController,
        builder:
            (context, child) {
          final t =
              _autoPulseController
                  .value;

          return Transform.scale(
            scale:
                1.0 +
                    (0.025 * t),
            child: Container(
              width:
                  double.infinity,
              padding:
                  const EdgeInsets.all(
                20,
              ),
              decoration:
                  BoxDecoration(
                gradient:
                    AppColors
                        .cardGradient,
                boxShadow: [
                  BoxShadow(
                    color: Colors
                        .black
                        .withOpacity(
                      0.25 +
                          (0.2 * t),
                    ),
                    blurRadius:
                        16 +
                            (14 * t),
                    offset:
                        Offset(
                      0,
                      6 +
                          (6 * t),
                    ),
                  ),
                ],
              ),
              child: child,
            ),
          );
        },
        child: Column(
          children: [
            Text(
              'استمع إلى أحدث المواعظ والبرامج والخطب العلمية',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color:
                    AppColors
                        .lightText,
                fontWeight:
                    FontWeight.w500,
              ),
            ),
            const SizedBox(
              height: 16,
            ),
            ElevatedButton(
              onPressed:
                  widget.onBrowseTap,
              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    AppColors
                        .primaryTeal,
                foregroundColor:
                    AppColors
                        .background,
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                ),
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              child:
                  const Text(
                'تصفح كل الأقسام',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LectureCard
    extends StatefulWidget {
  final Lecture lecture;
  final VoidCallback onTap;

  const _LectureCard({
    required this.lecture,
    required this.onTap,
  });

  @override
  State<_LectureCard> createState() =>
      _LectureCardState();
}

class _LectureCardState
    extends State<_LectureCard> {
  bool _pressed = false;

  void _setPressed(
    bool value,
  ) {
    setState(
      () => _pressed = value,
    );

    if (!value) {
      Future.delayed(
        const Duration(
          milliseconds: 500,
        ),
        () {
          if (mounted) {
            setState(() {});
          }
        },
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final audioService =
        AudioPlayerService.instance;

    final favoritesService =
        FavoritesService.instance;

    final downloadsService =
        DownloadsService.instance;

    return AnimatedBuilder(
      animation: Listenable.merge([
        audioService,
        favoritesService,
        downloadsService,
      ]),
      builder:
          (context, _) {
        final isThisPlaying =
            audioService
                        .currentLecture
                        ?.audioUrl ==
                    widget.lecture
                        .audioUrl &&
                audioService.isPlaying;

        final isFav =
            favoritesService
                .isFavorite(
          widget.lecture,
        );

        final isDownloaded =
            downloadsService
                .isDownloaded(
          widget.lecture,
        );

        final isDownloading =
            downloadsService
                .isDownloading(
          widget.lecture,
        );

        final progress =
            downloadsService
                .progressFor(
          widget.lecture,
        )
                .clamp(
          0.0,
          1.0,
        );

        return PulsingGlow(
          active:
              isThisPlaying,
          child:
              GestureDetector(
            onTapDown: (_) =>
                _setPressed(true),
            onTapUp: (_) =>
                setState(
              () =>
                  _pressed = false,
            ),
            onTapCancel: () =>
                setState(
              () =>
                  _pressed = false,
            ),
            onTap: widget.onTap,
            child:
                AnimatedScale(
              scale:
                  _pressed
                      ? 1.015
                      : 1.0,
              duration:
                  const Duration(
                milliseconds:
                    300,
              ),
              curve:
                  Curves.easeOut,
              child:
                  AnimatedContainer(
                duration:
                    const Duration(
                  milliseconds:
                      350,
                ),
                curve:
                    Curves.easeOut,
                transform:
                    Matrix4
                        .translationValues(
                  0,
                  _pressed ? -3 : 0,
                  0,
                ),
                padding:
                    const EdgeInsets
                        .fromLTRB(
                  14,
                  16,
                  14,
                  16,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      _pressed
                          ? const Color(
                              0xFF165652,
                            )
                          : AppColors
                              .cardDark,
                  borderRadius:
                      BorderRadius
                          .circular(
                    17,
                  ),
                  border:
                      Border.all(
                    width:
                        isThisPlaying
                            ? 1.5
                            : 1,
                    color:
                        isThisPlaying
                            ? AppColors
                                .primaryTeal
                            : _pressed
                                ? AppColors
                                    .primaryTeal
                                : AppColors
                                    .cardGradientStart
                                    .withOpacity(
                                  0.5,
                                ),
                  ),
                  boxShadow:
                      _pressed
                          ? [
                              BoxShadow(
                                color: Colors
                                    .black
                                    .withOpacity(
                                  0.4,
                                ),
                                blurRadius:
                                    20,
                                offset:
                                    const Offset(
                                  0,
                                  10,
                                ),
                              ),
                              BoxShadow(
                                color: AppColors
                                    .primaryTeal
                                    .withOpacity(
                                  0.25,
                                ),
                                blurRadius:
                                    15,
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
                                    7,
                                offset:
                                    const Offset(
                                  0,
                                  3,
                                ),
                              ),
                            ],
                ),
                child:
                    Row(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .center,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration:
                          BoxDecoration(
                        color: AppColors
                            .primaryTeal
                            .withOpacity(
                          0.12,
                        ),
                        shape:
                            BoxShape.circle,
                        border:
                            Border.all(
                          color: AppColors
                              .primaryTeal
                              .withOpacity(
                            0.35,
                          ),
                        ),
                      ),
                      child:
                          Icon(
                        isThisPlaying
                            ? Icons
                                .pause_rounded
                            : Icons
                                .play_arrow_rounded,
                        color: AppColors
                            .primaryTeal,
                        size: 27,
                      ),
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    GestureDetector(
                      onTap:
                          isDownloaded ||
                                  isDownloading
                              ? null
                              : () =>
                                  downloadsService
                                      .downloadLecture(
                                    widget
                                        .lecture,
                                  ),
                      child:
                          SizedBox(
                        width: 34,
                        height: 34,
                        child:
                            isDownloading
                                ? Stack(
                                    alignment:
                                        Alignment
                                            .center,
                                    children: [
                                      SizedBox(
                                        width:
                                            32,
                                        height:
                                            32,
                                        child:
                                            TweenAnimationBuilder<
                                                double>(
                                          tween:
                                              Tween<double>(
                                            begin:
                                                0,
                                            end:
                                                progress,
                                          ),
                                          duration:
                                              const Duration(
                                            milliseconds:
                                                250,
                                          ),
                                          curve:
                                              Curves
                                                  .easeOut,
                                          builder:
                                              (
                                            context,
                                            animatedProgress,
                                            _,
                                          ) {
                                            return CircularProgressIndicator(
                                              value:
                                                  animatedProgress,
                                              strokeWidth:
                                                  2.5,
                                              backgroundColor:
                                                  AppColors
                                                      .primaryTeal
                                                      .withOpacity(
                                                0.18,
                                              ),
                                              color:
                                                  AppColors
                                                      .primaryTeal,
                                            );
                                          },
                                        ),
                                      ),
                                      AnimatedSwitcher(
                                        duration:
                                            const Duration(
                                          milliseconds:
                                              180,
                                        ),
                                        child:
                                            Text(
                                          '${(progress * 100).round()}%',
                                          key:
                                              ValueKey(
                                            (progress * 100)
                                                .round(),
                                          ),
                                          style:
                                              TextStyle(
                                            fontSize:
                                                7,
                                            fontWeight:
                                                FontWeight.bold,
                                            color:
                                                AppColors
                                                    .primaryTeal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Icon(
                                    isDownloaded
                                        ? Icons
                                            .check_circle
                                        : Icons
                                            .download_rounded,
                                    color:
                                        AppColors
                                            .primaryTeal,
                                    size:
                                        22,
                                  ),
                      ),
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      child:
                          Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            widget.lecture
                                .title,
                            maxLines:
                                2,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                const TextStyle(
                              fontSize:
                                  14,
                              height:
                                  1.45,
                              fontWeight:
                                  FontWeight
                                      .bold,
                              color:
                                  AppColors
                                      .mainText,
                            ),
                          ),
                          const SizedBox(
                            height: 5,
                          ),
                          Text(
                            widget.lecture
                                .section,
                            maxLines:
                                1,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                TextStyle(
                              fontSize:
                                  11,
                              height:
                                  1.3,
                              fontWeight:
                                  FontWeight
                                      .w600,
                              color:
                                  AppColors
                                      .lightText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    GestureDetector(
                      onTap: () =>
                          favoritesService
                              .toggleFavorite(
                        widget.lecture,
                      ),
                      child:
                          Icon(
                        isFav
                            ? Icons.bookmark
                            : Icons
                                .bookmark_border,
                        color:
                            AppColors
                                .primaryTeal,
                        size: 22,
                      ),
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    GestureDetector(
                      onTap: () =>
                          ShareService
                              .shareLecture(
                        widget.lecture,
                      ),
                      child:
                          const Icon(
                        Icons
                            .share_outlined,
                        color:
                            AppColors
                                .primaryTeal,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
