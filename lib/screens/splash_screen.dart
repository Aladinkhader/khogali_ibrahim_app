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
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnim = Tween<double>(
      begin: 0.6,
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
      duration: const Duration(milliseconds: 850),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _controller.forward();

    Future.delayed(
      const Duration(milliseconds: 350),
      () {
        if (mounted) {
          _textController.forward();
        }
      },
    );

    Future.delayed(
      const Duration(milliseconds: 1250),
      () {
        if (mounted) {
          _shimmerController.forward();
        }
      },
    );

    Future.delayed(
      const Duration(milliseconds: 1900),
      () {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 500),
              pageBuilder: (_, anim, __) => const MainShell(),
              transitionsBuilder: (_, anim, __, child) {
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
      backgroundColor: AppColors.veryDarkBackground,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _PulsingAvatar(),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _textController,
                      _shimmerController,
                    ]),
                    builder: (context, child) {
                      final visibleCount =
                          (_textController.value * _title.length)
                              .floor()
                              .clamp(0, _title.length);

                      final visibleText = _title.substring(
                        0,
                        visibleCount,
                      );

                      return ShaderMask(
                        shaderCallback: (bounds) {
                          final shimmer = _shimmerController.value;

                          return const LinearGradient(
                            colors: [
                              AppColors.mainText,
                              _accent,
                              AppColors.mainText,
                            ],
                            stops: [
                              0.0,
                              0.5,
                              1.0,
                            ],
                          ).createShader(
                            Rect.fromLTWH(
                              bounds.left - (bounds.width * shimmer),
                              bounds.top,
                              bounds.width * 2,
                              bounds.height,
                            ),
                          );
                        },
                        blendMode: BlendMode.srcIn,
                        child: Text(
                          visibleText,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.tajawal(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            color: AppColors.mainText,
                            letterSpacing: 0.5,
                          ),
                        ),
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

class _PulsingAvatar extends StatefulWidget {
  const _PulsingAvatar();

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  static const Color _accent = Color(0xFF18C7DE);

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
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
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) {
              final value = _pulseController.value;

              return Opacity(
                opacity: (1 - value).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 1.0 + (value * 0.3),
                  child: Container(
                    width: 144,
                    height: 144,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _accent.withOpacity(0.4),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Container(
            width: 144,
            height: 144,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.cardDark,
              border: Border.all(
                color: _accent,
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
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
