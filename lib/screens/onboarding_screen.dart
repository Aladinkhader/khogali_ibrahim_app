import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import 'main_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();

  late final AnimationController _animationController;

  int _currentPage = 0;

  final List<_OnboardingItem> _items = const [
    _OnboardingItem(
      icon: Icons.menu_book_rounded,
      title: 'محاضرات الشيخ',
      description:
          'استمع إلى محاضرات الشيخ أبو الحسن خوجلي إبراهيم بسهولة وفي مكان واحد.',
    ),
    _OnboardingItem(
      icon: Icons.category_rounded,
      title: 'أقسام مرتبة',
      description:
          'تصفح المحاضرات حسب الأقسام والوصول إلى ما تبحث عنه بسرعة.',
    ),
    _OnboardingItem(
      icon: Icons.headphones_rounded,
      title: 'استماع مريح',
      description:
          'استمتع بتجربة استماع بسيطة وسلسة مع مشغل صوتي مخصص للمحاضرات.',
    ),
    _OnboardingItem(
      icon: Icons.download_rounded,
      title: 'استماع دون إنترنت',
      description:
          'حمّل المحاضرات واستمع إليها لاحقًا دون الحاجة إلى اتصال بالإنترنت.',
    ),
  ];

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _restartAnimation() {
    _animationController
      ..reset()
      ..forward();
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      'khogali_onboarding_completed',
      true,
    );

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, animation, __) => const MainShell(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  void _nextPage() {
    if (_currentPage < _items.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _skip() {
    _finishOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final bool isLastPage = _currentPage == _items.length - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.topEnd,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  top: 8,
                  end: 18,
                ),
                child: TextButton(
                  onPressed: _skip,
                  child: Text(
                    'تخطي',
                    style: GoogleFonts.tajawal(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _items.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });

                  _restartAnimation();
                },
                itemBuilder: (context, index) {
                  return _OnboardingPage(
                    item: _items[index],
                    animation: _animationController,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                24,
                8,
                24,
                28,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _items.length,
                      (index) {
                        final bool selected = index == _currentPage;

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          width: selected ? 28 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primaryTeal
                                : Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryTeal,
                        foregroundColor: Colors.white,
                        elevation: 8,
                        shadowColor:
                            AppColors.primaryTeal.withOpacity(0.30),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        isLastPage ? 'ابدأ الآن' : 'التالي',
                        style: GoogleFonts.tajawal(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingItem item;
  final Animation<double> animation;

  const _OnboardingPage({
    required this.item,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Opacity(
          opacity: animation.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.82 + (curvedAnimation.value * 0.18),
            child: Transform.translate(
              offset: Offset(
                0,
                35 * (1 - animation.value),
              ),
              child: child,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 2),

            Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primaryTeal.withOpacity(0.22),
                    AppColors.primaryTeal.withOpacity(0.07),
                    Colors.transparent,
                  ],
                  stops: const [
                    0.0,
                    0.55,
                    1.0,
                  ],
                ),
              ),
              child: Center(
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.cardDark,
                    border: Border.all(
                      color: AppColors.primaryTeal,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryTeal.withOpacity(0.20),
                        blurRadius: 35,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.30),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    item.icon,
                    color: AppColors.primaryTeal,
                    size: 64,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 48),

            Text(
              item.title,
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 16),

            Text(
              item.description,
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                color: Colors.white.withOpacity(0.82),
                fontSize: 16,
                height: 1.9,
                fontWeight: FontWeight.w500,
              ),
            ),

            const Spacer(flex: 3),
          ],
        ),
      ),
    );
  }
}

class _OnboardingItem {
  final IconData icon;
  final String title;
  final String description;

  const _OnboardingItem({
    required this.icon,
    required this.title,
    required this.description,
  });
}
