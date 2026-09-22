import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'player/audio_handler.dart';
import 'screens/player_screen.dart';
import 'services/music_service.dart';
import 'theme/retro_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa o serviço de áudio antes de mostrar a UI.
  // Assim o PlayerScreen já recebe o handler pronto, sem polling.
  TsukiAudioHandler? audioHandler;

  try {
    audioHandler = await AudioService.init(
      builder: () => TsukiAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId:
            'com.lesano.tsukiplayer.audio',
        androidNotificationChannelName:
            'Tsuki Player',
        androidNotificationChannelDescription:
            'Controlos de reprodução do Tsuki Player',
        androidNotificationIcon:
            'drawable/ic_notification',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
      ),
    );
  } catch (e) {
    // Se falhar, a UI ainda abre; o player fica sem suporte
    // de notificação/bluetooth.
  }

  runApp(TsukiPlayerApp(audioHandler: audioHandler));
}

class TsukiPlayerApp extends StatefulWidget {
  const TsukiPlayerApp({super.key, this.audioHandler});

  final TsukiAudioHandler? audioHandler;

  @override
  State<TsukiPlayerApp> createState() => _TsukiPlayerAppState();
}

class _TsukiPlayerAppState extends State<TsukiPlayerApp> {
  final ValueNotifier<RetroColors> _palette = ValueNotifier(
    RetroColors.green,
  );

  @override
  void initState() {
    super.initState();

    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final index = await MusicService().getThemeIndex();

    _palette.value = RetroColors.all[index.clamp(0, RetroColors.all.length - 1)];
  }

  @override
  void dispose() {
    _palette.dispose();

    super.dispose();
  }

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
        child: ValueListenableBuilder<RetroColors>(
          valueListenable: _palette,
          builder: (context, palette, _) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: palette.primary,
                        width: 2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: PlayerScreen(
                        audioHandler: widget.audioHandler,
                        palette: _palette,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}