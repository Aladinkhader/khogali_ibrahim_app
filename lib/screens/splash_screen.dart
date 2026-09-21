import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import 'main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  late final AnimationController _textController;
  late final AnimationController _shimmerController;

  static const Color _accent = Color(0xFF18C7DE);

  static const String _title = 'الشيخ أبو الحسن خوجلي إبراهيم';

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnim = Tween<double>(
      begin: 0.72,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );

    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeIn,
      ),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _controller.forward();

    Future.delayed(
      const Duration(milliseconds: 500),
      () {
        if (mounted) {
          _textController.forward();
        }
      },
    );

    Future.delayed(
      const Duration(milliseconds: 850),
      () {
        if (mounted) {
          _shimmerController.repeat();
        }
      },
    );

    /*
     * نترك وقتًا كافيًا للمستخدم لقراءة الاسم
     * بعد اكتمال ظهوره.
     */
    Future.delayed(
      const Duration(milliseconds: 5200),
      () {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              transitionDuration:
                  const Duration(milliseconds: 650),
              pageBuilder: (_, anim, __) =>
                  const MainShell(),
              transitionsBuilder:
                  (_, anim, __, child) {
                return FadeTransition(
                  opacity: anim,
                  child: child,
                );
              },
            ),
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _textController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          AppColors.veryDarkBackground,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _PulsingAvatar(),

                const SizedBox(height: 28),

                Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 24,
                  ),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _textController,
                      _shimmerController,
                    ]),
                    builder:
                        (context, child) {
                      final progress =
                          _textController.value;

                      final visibleCount =
                          (progress *
                                  _title.length)
                              .floor()
                              .clamp(
                                0,
                                _title.length,
                              );

                      final visibleText =
                          _title.substring(
                        0,
                        visibleCount,
                      );

                      /*
                       * الضوء يتحرك مع الحرف الجاري ظهوره.
                       *
                       * بعد أن يظهر الحرف:
                       * يبقى أبيض.
                       *
                       * السماوي يظهر فقط حول
                       * منطقة الحرف الجديد.
                       */
                      final currentPosition =
                          progress *
                              _title.length;

                      return Stack(
                        alignment:
                            Alignment.center,
                        children: [
                          /*
                           * النص الأساسي:
                           * كل الحروف التي ظهرت
                           * لونها أبيض دائمًا.
                           */
                          Text(
                            visibleText,
                            textAlign:
                                TextAlign.center,
                            style:
                                GoogleFonts.tajawal(
                              fontSize: 24,
                              fontWeight:
                                  FontWeight.w900,
                              color:
                                  AppColors.mainText,
                              letterSpacing: 0.5,
                            ),
                          ),

                          /*
                           * طبقة الضوء السماوي.
                           *
                           * تظهر فقط أثناء دخول
                           * الحرف الجديد، وليس على
                           * كامل الكلمة.
                           */
                          if (visibleCount <
                              _title.length)
                            _ShimmerCharacter(
                              title: _title,
                              visibleCount:
                                  visibleCount,
                              progress:
                                  currentPosition -
                                      visibleCount,
                              accent: _accent,
                            ),
                        ],
                      );
                    },
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

class _ShimmerCharacter
    extends StatelessWidget {
  final String title;
  final int visibleCount;
  final double progress;
  final Color accent;

  const _ShimmerCharacter({
    required this.title,
    required this.visibleCount,
    required this.progress,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (visibleCount >= title.length) {
      return const SizedBox.shrink();
    }

    /*
     * الحرف الحالي.
     */
    final currentCharacter =
        title[visibleCount];

    /*
     * إذا كان الحرف مسافة،
     * لا نعرض ضوءًا عليها.
     */
    if (currentCharacter == ' ') {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: ShaderMask(
        shaderCallback: (bounds) {
          /*
           * الضوء يمر من اليمين إلى اليسار
           * داخل الحرف الحالي.
           */
          final position =
              progress.clamp(0.0, 1.0);

          return LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [
              accent.withOpacity(0.0),
              accent,
              accent.withOpacity(0.0),
            ],
            stops: [
              (position - 0.35)
                  .clamp(0.0, 1.0),
              position.clamp(0.0, 1.0),
              (position + 0.35)
                  .clamp(0.0, 1.0),
            ],
          ).createShader(
            Rect.fromLTWH(
              bounds.left,
              bounds.top,
              bounds.width,
              bounds.height,
            ),
          );
        },
        blendMode: BlendMode.srcIn,
        child: Text(
          currentCharacter,
          textAlign: TextAlign.center,
          style: GoogleFonts.tajawal(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: accent,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _PulsingAvatar
    extends StatefulWidget {
  const _PulsingAvatar();

  @override
  State<_PulsingAvatar> createState() =>
      _PulsingAvatarState();
}

class _PulsingAvatarState
    extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController
      _pulseController;

  static const Color _accent =
      Color(0xFF18C7DE);

  @override
  void initState() {
    super.initState();

    _pulseController =
        AnimationController(
      vsync: this,
      duration:
          const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation:
                _pulseController,
            builder: (_, __) {
              final value =
                  _pulseController.value;

              return Opacity(
                opacity:
                    (1 - value)
                        .clamp(0.0, 1.0),
                child:
                    Transform.scale(
                  scale:
                      1.0 +
                          (value * 0.3),
                  child: Container(
                    width: 164,
                    height: 164,
                    decoration:
                        BoxDecoration(
                      shape:
                          BoxShape.circle,
                      border:
                          Border.all(
                        color: _accent
                            .withOpacity(
                          0.4,
                        ),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Container(
            width: 164,
            height: 164,
            padding:
                const EdgeInsets.all(4),
            decoration:
                BoxDecoration(
              shape:
                  BoxShape.circle,
              color:
                  AppColors.cardDark,
              border:
                  Border.all(
                color: _accent,
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withOpacity(
                    0.4,
                  ),
                  blurRadius: 20,
                  offset:
                      const Offset(
                    0,
                    8,
                  ),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/khogali.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
