import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/favorites_service.dart';
import 'services/audio_player_service.dart';
import 'services/downloads_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? initError;

  try {
    await JustAudioBackground.init(
      androidNotificationChannelId:
          'sheikh_khogali_ibrahim.channel.media',
      androidNotificationChannelName:
          'مشغل محاضرات الشيخ أبو الحسن خوجلي إبراهيم',
      androidNotificationChannelDescription:
          'التحكم في تشغيل محاضرات الشيخ أبو الحسن خوجلي إبراهيم من شريط الإشعارات',
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,
    );

    await FavoritesService.instance.init();
    await DownloadsService.instance.init();
    await AudioPlayerService.instance.init();
  } catch (e) {
    initError = e.toString();
  }

  runApp(
    SheikhApp(
      initError: initError,
    ),
  );
}

class SheikhApp extends StatelessWidget {
  final String? initError;

  const SheikhApp({
    super.key,
    this.initError,
  });

  @override
  Widget build(BuildContext context) {
    if (initError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'تعذر تشغيل بعض خدمات التطبيق.\nيرجى إعادة تشغيل التطبيق والمحاولة مرة أخرى.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'الشيخ أبو الحسن خوجلي إبراهيم',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
