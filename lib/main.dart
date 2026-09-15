import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'player/audio_handler.dart';
import 'screens/player_screen.dart';

TsukiAudioHandler? audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A interface inicia imediatamente.
  runApp(const TsukiPlayerApp());

  // Inicializa o serviço de áudio depois da UI aparecer.
  AudioService.init(
    builder: () => TsukiAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId:
          'com.lesano.tsukiplayer.audio',
      androidNotificationChannelName:
          'Tsuki Player',
      androidNotificationChannelDescription:
          'Controlos de reprodução do Tsuki Player',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  ).then((handler) {
    audioHandler = handler;
  });
}

class TsukiPlayerApp extends StatelessWidget {
  const TsukiPlayerApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Minecraftia',
        scaffoldBackgroundColor: Colors.black,
      ),
      home: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarContrastEnforced: false,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.green,
                    width: 2,
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: PlayerScreen(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}