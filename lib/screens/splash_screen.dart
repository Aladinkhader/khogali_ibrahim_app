import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';

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

  static const Color _accent = AppColors.primaryTeal;

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
      duration: const Duration(milliseconds: 1800),
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
      const Duration(milliseconds: 900),
      () {
        if (mounted) {
          _shimmerController.repeat();
        }
      },
    );

    Future.delayed(
      const Duration(milliseconds: 5200),
      () {
        if (mounted) {
          _openNextScreen();
        }
      },
    );
  }

  Future<void> _openNextScreen() async {
    final prefs = await SharedPreferences.getInstance();

    final bool onboardingCompleted = prefs.getBool(
          'khogali_onboarding_completed',
        ) ??
        false;

    if (!mounted) return;

    final Widget nextScreen = onboardingCompleted
        ? const MainShell()
        : const OnboardingScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 650),
        pageBuilder: (_, animation, __) => nextScreen,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
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

                const SizedBox(height: 28),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                  ),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _textController,
                      _shimmerController,
                    ]),
                    builder: (context, child) {
                      final double progress = _textController.value;

                      final int visibleCount = (progress * _title.length)
                          .floor()
                          .clamp(0, _title.length);

                      final String visibleText = _title.substring(
                        0,
                        visibleCount,
                      );

                      return _ShimmerText(
                        text: visibleText,
                        shimmerProgress: _shimmerController.value,
                        accent: _accent,
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

class _ShimmerText extends StatelessWidget {
  final String text;
  final double shimmerProgress;
  final Color accent;

  const _ShimmerText({
    required this.text,
    required this.shimmerProgress,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    const TextStyle textStyle = TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w900,
      color: AppColors.mainText,
      letterSpacing: 0.5,
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.tajawal(
            fontSize: textStyle.fontSize,
            fontWeight: textStyle.fontWeight,
            color: AppColors.mainText,
            letterSpacing: textStyle.letterSpacing,
          ),
        ),
        IgnorePointer(
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              final double center = -0.35 + (shimmerProgress * 1.7);

              const double width = 0.16;

              final double start = (center - width).clamp(-1.0, 1.0);

              final double end = (center + width).clamp(-1.0, 1.0);

              final double leftFade =
                  (center - width * 2.2).clamp(-1.0, 1.0);

              final double rightFade =
                  (center + width * 2.2).clamp(-1.0, 1.0);

              return LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  accent.withOpacity(0.15),
                  accent.withOpacity(0.95),
                  accent,
                  accent.withOpacity(0.95),
                  accent.withOpacity(0.15),
                  Colors.transparent,
                  Colors.transparent,
                ],
                stops: [
                  0.0,
                  ((leftFade + 1) / 2).clamp(0.0, 1.0),
                  ((center - width * 1.4 + 1) / 2).clamp(0.0, 1.0),
                  ((start + 1) / 2).clamp(0.0, 1.0),
                  ((center + 1) / 2).clamp(0.0, 1.0),
                  ((end + 1) / 2).clamp(0.0, 1.0),
                  ((center + width * 1.4 + 1) / 2).clamp(0.0, 1.0),
                  ((rightFade + 1) / 2).clamp(0.0, 1.0),
                  1.0,
                ],
              ).createShader(bounds);
            },
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: accent,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
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

  static const Color _accent = AppColors.primaryTeal;

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
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) {
              final double value = _pulseController.value;

              return Opacity(
                opacity: (1 - value).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 1.0 + (value * 0.3),
                  child: Container(
                    width: 164,
                    height: 164,
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
            width: 164,
            height: 164,
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
