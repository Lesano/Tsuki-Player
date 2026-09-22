import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import '../player/audio_handler.dart';
import '../services/music_service.dart';
import '../theme/retro_colors.dart';
import '../utils/sleep_timer.dart';
import '../widgets/retro_equalizer.dart';
import '../widgets/retro_marquee.dart';
import '../widgets/retro_seek_bar.dart';
import '../widgets/retro_volume.dart';

enum RepeatMode {
  off,
  all,
  one,
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, this.audioHandler, this.palette});

  final TsukiAudioHandler? audioHandler;

  final ValueNotifier<RetroColors>? palette;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final MusicService musicService = MusicService();

  TsukiAudioHandler? audioPlayer;

  late RetroColors _palette;

  Color get green => _palette.primary;

  Color get darkGreen => _palette.dark;

  Color get darkerGreen => _palette.darker;

  List<Song> songs = [];

  int currentSongIndex = 0;

  bool isLoading = true;
  bool isPlaying = false;

  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<ProcessingState>? _processingStateSubscription;
Duration position = Duration.zero;
  Duration duration = Duration.zero;

  // ============================================================
  // FAVORITAS
  // ============================================================

  Set<String> _favorites = {};
  bool _favoritesOnly = false;
  String _playlistQuery = '';
  String _playlistOrder = 'n';
  final TextEditingController _playlistSearchController =
      TextEditingController();

  int _resumeIndex = 0;
  Duration? _pendingResumePosition;
  DateTime _lastPositionSave = DateTime.fromMillisecondsSinceEpoch(0);

  bool _fullscreen = false;
  // ============================================================
  // MODOS DE REPRODUÇÃO
  // ============================================================

  bool isShuffle = false;
  RepeatMode repeatMode = RepeatMode.off;

  final Random _random = Random();

  // Guarda músicas já preparadas para evitar novo processamento
  // de metadata/capa ao voltar para uma faixa.
  final Map<String, Song> _preparedSongs = {};

  // Histórico simples do modo aleatório.
  final List<int> _shuffleHistory = [];
  int _shuffleHistoryPosition = -1;

  // ============================================================
  // VOLUME + TIMER DE DESLIGAMENTO
  // ============================================================

  double _volume = 1.0;

  Timer? _sleepTimer;
  Timer? _sleepTicker;
  DateTime? _sleepTimerEnd;
  int _sleepMinutes = 0;

  // Fade-out do timer de desligamento.
  bool _sleepFadeActive = false;
  static const int _sleepFadeSteps = 10;
  static const Duration _sleepFadeStepDuration =
      Duration(milliseconds: 120);

  int get _sleepRemainingSeconds {
    final end = _sleepTimerEnd;

    if (end == null) {
      return 0;
    }

    final remaining = end.difference(DateTime.now()).inSeconds;

    return remaining < 0 ? 0 : remaining;
  }

  // ============================================================
  // MÚSICA ATUAL
  // ============================================================

  Song? get currentSong {
    if (songs.isEmpty) {
      return null;
    }

    if (currentSongIndex >= songs.length) {
      return null;
    }

    return songs[currentSongIndex];
  }

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    audioPlayer = widget.audioHandler;

    _palette = widget.palette?.value ?? RetroColors.green;

    widget.palette?.addListener(_onPaletteChanged);

    _initialize();
  }

  void _onPaletteChanged() {
    if (!mounted) {
      return;
    }

    setState(() {
      _palette = widget.palette!.value;
    });
  }

  // ============================================================
  // INICIALIZAÇÃO
  // ============================================================

  Future<void> _initialize() async {
    await _loadVolume();

    await _loadFavorites();

    _resumeIndex = await musicService.getLastSongIndex();

    final resumeMs = await musicService.getLastPositionMs();

    _pendingResumePosition = resumeMs > 0
        ? Duration(milliseconds: resumeMs)
        : null;

    await _loadSavedMusic();

    await _connectAudioHandler();
  }

  // ============================================================
  // FAVORITAS
  // ============================================================

  Future<void> _loadFavorites() async {
    final favorites = await musicService.getFavorites();

    _favorites = favorites.toSet();
  }

  Future<void> _toggleFavorite(String file) async {
    final isFavorite = await musicService.toggleFavorite(file);

    if (!mounted) {
      return;
    }

    setState(() {
      if (isFavorite) {
        _favorites.add(file);
      } else {
        _favorites.remove(file);
      }
    });
  }

  // ============================================================
  // VOLUME
  // ============================================================

  Future<void> _loadVolume() async {
    final volume = await musicService.getVolume();

    if (!mounted) {
      return;
    }

    setState(() {
      _volume = volume;
    });
  }

  // ============================================================
  // AUDIO HANDLER
  // ============================================================

  Future<void> _connectAudioHandler() async {
    if (audioPlayer == null) {
      return;
    }

    // ==========================================================
    // CONTROLOS DA NOTIFICAÇÃO
    // ==========================================================

    audioPlayer!.onNextSong = _nextSong;

    audioPlayer!.onPreviousSong = _previousSong;

    // ==========================================================
    // PLAY / PAUSE
    // ==========================================================

    _playingSubscription = audioPlayer!.playingStream.listen((playing) {
      if (!mounted) {
        return;
      }

      setState(() {
        isPlaying = playing;
      });
    });

    // ==========================================================
    // POSIÇÃO
    // ==========================================================

    _positionSubscription = audioPlayer!.positionStream.listen((newPosition) {
      if (!mounted) {
        return;
      }

      setState(() {
        position = newPosition;

        final currentDuration = audioPlayer?.duration;

        if (currentDuration != null) {
          duration = currentDuration;
        }
      });

      // Guarda a posição a cada ~5s para retomar depois.
      if (newPosition.inSeconds > 0 &&
          DateTime.now().difference(_lastPositionSave).inSeconds >= 5) {
        _lastPositionSave = DateTime.now();

        musicService.saveLastPositionMs(newPosition.inMilliseconds);
      }
    });

    // ==========================================================
    // AUTO-NEXT
    // ==========================================================

    _processingStateSubscription = audioPlayer!.processingStateStream.listen((
      state,
    ) async {
      if (state == ProcessingState.completed) {
        await _nextSong(automatic: true);
      }
    });

    // ==========================================================
    // VOLUME GUARDADO
    // ==========================================================

    await audioPlayer!.setVolume(_volume);
  }

  // ============================================================
  // BIBLIOTECA
  // ============================================================

  Future<void> _loadSavedMusic() async {
    List<Song> loadedSongs;

    try {
      loadedSongs = await musicService.loadSavedMusic();
    } catch (e) {
      // Permissão removida ou pasta inacessível.
      if (!mounted) {
        return;
      }

      setState(() {
        songs = [];
        isLoading = false;
      });

      _showError('Não foi possível abrir a pasta guardada.');
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      songs = loadedSongs;
      currentSongIndex = _resumeIndex < songs.length ? _resumeIndex : 0;
      isLoading = false;
    });

    // Caso o AudioHandler já esteja disponível.
    if (songs.isNotEmpty && audioPlayer != null) {
      await _loadCurrentSong();
    }
  }

  // ============================================================
  // ESCOLHER PASTA
  // ============================================================

  Future<void> _chooseMusicFolder() async {
    setState(() {
      isLoading = true;
    });

    List<Song> loadedSongs;

    try {
      loadedSongs = await musicService.chooseMusicFolder();
    } catch (e) {
      // Falha ao abrir a SAF ou a ler a pasta.
      if (!mounted) {
        return;
      }

      setState(() {
        isLoading = false;
      });

      _showError('Não foi possível ler a pasta selecionada.');
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      songs = loadedSongs;
      currentSongIndex = 0;
      isLoading = false;
    });

    _pendingResumePosition = null;

    await musicService.saveLastSongIndex(0);

    await musicService.saveLastPositionMs(0);

    if (songs.isNotEmpty && audioPlayer != null) {
      await _loadCurrentSong();

      // Ao escolher uma pasta nova, a primeira música toca automaticamente.
      await audioPlayer!.play();
    }
  }

  // ============================================================
  // CARREGAR MÚSICA
  // ============================================================

  Future<void> _loadCurrentSong() async {
    final song = currentSong;

    if (song == null || audioPlayer == null) {
      return;
    }

    try {
      // Para a faixa atual antes de trocar, evitando bug
      // ao carregar a nova música (playlist, anterior, seguinte, pasta).
      if (audioPlayer!.playing) {
        await audioPlayer!.pause();
      }

      // ========================================================
      // METADATA + CAPA
      // ========================================================

      // Se já preparámos esta música, reutiliza os dados.
      // Isto elimina o processamento repetido ao trocar de faixa.
      final preparedSong =
          _preparedSongs[song.file] ??
          await musicService.prepareSong(song);

      _preparedSongs[song.file] = preparedSong;

      // Mantém o cache limitado para não crescer sem limite.
      if (_preparedSongs.length > 60) {
        _preparedSongs.remove(_preparedSongs.keys.first);
      }

      if (!mounted) {
        return;
      }

      // Guarda metadata/capa na playlist.
      setState(() {
        songs[currentSongIndex] = preparedSong;
      });

      // ========================================================
      // CARREGAR ÁUDIO
      // ========================================================

      await audioPlayer!.setFilePath(preparedSong.file);

      // ========================================================
      // RETOMAR ONDE PAROU
      // ========================================================

      final resumePosition = _pendingResumePosition;

      _pendingResumePosition = null;

      _lastPositionSave = DateTime.fromMillisecondsSinceEpoch(0);

      if (resumePosition != null) {
        await audioPlayer!.seek(resumePosition);

        await musicService.saveLastPositionMs(resumePosition.inMilliseconds);
      } else {
        // Nova música: nunca herdar a posição da faixa anterior.
        await musicService.saveLastPositionMs(0);
      }

      await musicService.saveLastSongIndex(currentSongIndex);

      // ========================================================
      // ATUALIZAR NOTIFICAÇÃO
      // ========================================================

      await audioPlayer!.setCurrentMediaItem(
        file: preparedSong.file,
        title: preparedSong.title,
        artist: preparedSong.artist,
        artwork: preparedSong.cover,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        duration = audioPlayer!.duration ?? Duration.zero;
        position = resumePosition ?? Duration.zero;
      });

    } catch (e) {
      // Mantém o player utilizável e avisa o utilizador.
      if (mounted) {
        _showError('Não foi possível carregar "${song.title}".');
      }
    }
  }

  // ============================================================
  // SELECIONAR MÚSICA
  // ============================================================

  Future<void> _selectSong(int index) async {
    if (index < 0 || index >= songs.length) {
      return;
    }

    // O toque na linha da playlist já fechou o sheet com pop();
    // aqui só troca de faixa para não fechar a tela (root) a mais.
    setState(() {
      currentSongIndex = index;
    });

    await _loadCurrentSong();
  }

  // ============================================================
  // PLAY / PAUSE
  // ============================================================

  Future<void> _togglePlay() async {
    if (audioPlayer == null || currentSong == null) {
      return;
    }

    try {
      if (audioPlayer!.playing) {
        await audioPlayer!.pause();
      } else {
        // Retomar: devolve o volume original (ex.: após fade-out).
        await audioPlayer!.setVolume(_volume);

        await audioPlayer!.play();
      }
    } catch (e) {
      // O handler continua disponível; apenas informa o utilizador.
      if (mounted) {
        _showError('Não foi possível reproduzir a música.');
      }
    }
  }

  // ============================================================
  // FEEDBACK DE ERROS
  // ============================================================

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(fontFamily: 'Minecraftia'),
          ),
          backgroundColor: darkGreen,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  // ============================================================
  // ANTERIOR
  // ============================================================

  Future<void> _previousSong() async {
    if (songs.isEmpty || audioPlayer == null) {
      return;
    }

    // Se já passou de 3 segundos, reinicia a música atual.
    if (audioPlayer!.position.inSeconds >= 3) {
      await audioPlayer!.seek(Duration.zero);
      return;
    }

    // No modo aleatório, tenta voltar pelo histórico.
    if (isShuffle && _shuffleHistoryPosition > 0) {
      _shuffleHistoryPosition--;

      final previousIndex =
          _shuffleHistory[_shuffleHistoryPosition];

      if (mounted) {
        setState(() {
          currentSongIndex = previousIndex;
        });
      }

      await _loadCurrentSong();

      return;
    }

    if (currentSongIndex == 0) {
      await audioPlayer!.seek(Duration.zero);
      return;
    }

    final wasPlaying = audioPlayer!.playing;

    if (mounted) {
      setState(() {
        currentSongIndex--;
      });
    }

    await _loadCurrentSong();

    if (wasPlaying) {
      await audioPlayer!.play();
    }
  }

  // ============================================================
  // PRÓXIMA
  // ============================================================

  Future<void> _nextSong({bool automatic = false}) async {
    if (songs.isEmpty || audioPlayer == null) {
      return;
    }

    // REPETIR UMA
    // Quando a música termina, volta ao início da mesma faixa.
    if (automatic && repeatMode == RepeatMode.one) {
      await audioPlayer!.seek(Duration.zero);
      await audioPlayer!.play();
      return;
    }

    int nextIndex = currentSongIndex;

    // ALEATÓRIO
    if (isShuffle && songs.length > 1) {
      final availableIndexes = <int>[
        for (int i = 0; i < songs.length; i++)
          if (i != currentSongIndex) i,
      ];

      nextIndex =
          availableIndexes[
            _random.nextInt(availableIndexes.length)
          ];

      // Mantém histórico para o botão anterior.
      if (_shuffleHistoryPosition <
          _shuffleHistory.length - 1) {
        _shuffleHistory.removeRange(
          _shuffleHistoryPosition + 1,
          _shuffleHistory.length,
        );
      }

      if (_shuffleHistory.isEmpty ||
          _shuffleHistory.last != currentSongIndex) {
        _shuffleHistory.add(currentSongIndex);
      }

      _shuffleHistory.add(nextIndex);
      _shuffleHistoryPosition =
          _shuffleHistory.length - 1;
    } else {
      // NORMAL
      if (currentSongIndex < songs.length - 1) {
        nextIndex = currentSongIndex + 1;
      } else if (repeatMode == RepeatMode.all) {
        nextIndex = 0;
      } else {
        // Sem repetir e chegou ao fim.
        if (automatic) {

          await audioPlayer!.pause();
          await audioPlayer!.seek(Duration.zero);

          if (!mounted) {
            return;
          }

          setState(() {
            position = Duration.zero;
            isPlaying = false;
          });

          return;
        }

        // Próxima manual na última faixa:
        // mantém o comportamento anterior e volta ao início.
        await audioPlayer!.seek(Duration.zero);
        return;
      }
    }

    if (mounted) {
      setState(() {
        currentSongIndex = nextIndex;
      });
    }

    await _loadCurrentSong();

    // A próxima faixa toca automaticamente.
    await audioPlayer!.play();
  }

  // ============================================================
  // MODOS
  // ============================================================

  void _volumeChanged(double value) {
    setState(() {
      _volume = value;
    });
  }

  Future<void> _volumeChangeEnd(double value) async {
    _volume = value;

    await audioPlayer?.setVolume(value);

    await musicService.saveVolume(value);
  }

  // ============================================================
  // TIMER DE DESLIGAMENTO
  // ============================================================

  void _setSleepTimer(int minutes) {
    // Cancela qualquer fade-out em andamento (restaura o volume).
    _sleepFadeActive = false;

    _sleepTimer?.cancel();
    _sleepTicker?.cancel();

    setState(() {
      _sleepMinutes = minutes;
      _sleepTimerEnd = minutes > 0
          ? DateTime.now().add(Duration(minutes: minutes))
          : null;
    });

    if (minutes <= 0) {
      return;
    }

    _sleepTimer = Timer(
      Duration(minutes: minutes),
      _onSleepTimerFinished,
    );

    // Atualiza o contador ao lado da lua a cada segundo.
    _sleepTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) {
          return;
        }

        if (_sleepRemainingSeconds <= 0) {
          _onSleepTimerFinished();
          return;
        }

        setState(() {});
      },
    );

    _showSleepSnackBar('☾ Timer ligado · $minutes MIN');
  }

  void _showSleepSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(fontFamily: 'Minecraftia'),
          ),
          backgroundColor: darkGreen,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  String _sleepTimerLabel() {
    final s = _sleepRemainingSeconds;
    final m = s ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');

    return '$m:$sec';
  }

  Widget _sleepTimerButton({double iconSize = 21, double splashRadius = 22}) {
    final active = _sleepMinutes > 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _showSleepTimerPicker,
          tooltip: 'Timer de desligamento',
          splashRadius: splashRadius,
          icon: Icon(
            Icons.bedtime,
            size: iconSize,
            color: active ? green : green.withAlpha(85),
          ),
        ),
        if (active) ...[
          const SizedBox(width: 2),
          Text(
            _sleepTimerLabel(),
            style: TextStyle(
              fontFamily: 'Minecraftia',
              color: green.withAlpha(220),
              fontSize: 7,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _onSleepTimerFinished() async {
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();

    final player = audioPlayer;

    // Toca: faz fade-out suave antes de pausar, como num MP3 player.
    if (player != null && player.playing) {
      await _runSleepFadeOut();
      return;
    }

    // Já pausado: apenas reinicia o estado.
    await player?.pause();

    _resetSleepState();
  }

  Future<void> _runSleepFadeOut() async {
    final originalVolume = _volume;
    final player = audioPlayer;

    _sleepFadeActive = true;

    var step = _sleepFadeSteps;

    while (mounted && _sleepFadeActive && step > 0) {
      await player?.setVolume(
        fadeTargetVolume(originalVolume, step, _sleepFadeSteps),
      );

      step--;

      if (step > 0 && _sleepFadeActive) {
        await Future.delayed(_sleepFadeStepDuration);
      }
    }

    // Fim do fade: pausa no volume 0 e só então restaura o volume original,
    // para o ouvinte não ouvir a música "voltar ao normal" antes de parar.
    if (step <= 0) {
      await player?.setVolume(0.0);
      await player?.pause();
    }

    // Restaura o volume original (silencioso, já pausado).
    await player?.setVolume(originalVolume);

    _sleepFadeActive = false;

    // Só reinicia o estado se o fade chegou ao fim sem interrupção.
    if (step <= 0) {
      _resetSleepState();
    }
  }

  void _resetSleepState() {
    if (!mounted) {
      return;
    }

    setState(() {
      _sleepMinutes = 0;
      _sleepTimerEnd = null;
    });

    _showSleepSnackBar('ZZZ · Timer desligado');
  }

  void _showSleepTimerPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(
              top: BorderSide(color: green, width: 2),
              left: BorderSide(color: green, width: 1),
              right: BorderSide(color: green, width: 1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),

              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: green,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'TIMER DE DESLIGAMENTO',
                style: TextStyle(
                  fontFamily: 'Minecraftia',
                  color: green,
                  fontSize: 15,
                  letterSpacing: 1,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                _sleepMinutes > 0
                    ? 'PARA EM $_sleepMinutes MIN'
                    : 'DESLIGADO',
                style: TextStyle(
                  fontFamily: 'Minecraftia',
                  color: green.withAlpha(160),
                  fontSize: 8,
                ),
              ),

              const SizedBox(height: 12),

              for (final option in _sleepOptions)
                _sleepOptionTile(option: option),

              _customSleepOptionTile(),

              const SizedBox(height: 18),
            ],
          ),
        );
      },
    );
  }

  static const List<(int, String)> _sleepOptions = [
    (0, 'DESLIGAR'),
    (5, '5 MIN'),
    (15, '15 MIN'),
    (30, '30 MIN'),
    (60, '60 MIN'),
  ];

  Widget _sleepOptionTile({required (int, String) option}) {
    final minutes = option.$1;
    final label = option.$2;
    final active = minutes == _sleepMinutes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () {
            Navigator.of(context).pop();

            _setSleepTimer(minutes);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: active ? darkGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: active ? green : green.withAlpha(35),
                width: active ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.bedtime, color: green, size: 16),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Minecraftia',
                      color: green,
                      fontSize: 9,
                    ),
                  ),
                ),

                if (active)
                  Icon(Icons.play_arrow, color: green, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _customSleepOptionTile() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () {
            Navigator.of(context).pop();

            _showCustomSleepTimer();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: green.withAlpha(90), width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.edit, color: green, size: 16),

                SizedBox(width: 12),

                Expanded(
                  child: Text(
                    'PERSONALIZADO...',
                    style: TextStyle(
                      fontFamily: 'Minecraftia',
                      color: green,
                      fontSize: 9,
                    ),
                  ),
                ),

                Icon(Icons.keyboard_arrow_right, color: green, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCustomSleepTimer() {
    // Começa do valor actual ou de 15 por defeito. Sem teclado:
    // o número é escolhido com os botões +/-, evitando o overlay
    // que aparecia ao abrir o teclado.
    var minutes = _sleepMinutes > 0 ? _sleepMinutes : 15;

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: green, width: 1.5),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 24,
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'TIMER PERSONALIZADO',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Minecraftia',
                        color: green,
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _stepperButton(
                          icon: Icons.remove,
                          onPressed: () {
                            setDialogState(() {
                              minutes = minutes > 1 ? minutes - 1 : 1;
                            });
                          },
                        ),
                        Container(
                          width: 64,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: darkGreen,
                            border: Border.all(color: green, width: 1.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$minutes',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Minecraftia',
                              color: green,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        _stepperButton(
                          icon: Icons.add,
                          onPressed: () {
                            setDialogState(() {
                              minutes = minutes < 120 ? minutes + 1 : 120;
                            });
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    Text(
                      '1 A 120 MIN',
                      style: TextStyle(
                        fontFamily: 'Minecraftia',
                        color: green.withAlpha(160),
                        fontSize: 7,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'CANCELAR',
                              style: TextStyle(
                                fontFamily: 'Minecraftia',
                                color: green,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();

                              _setSleepTimer(minutes);
                            },
                            child: Text(
                              'COMEÇAR',
                              style: TextStyle(
                                fontFamily: 'Minecraftia',
                                color: green,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _stepperButton({required IconData icon, required VoidCallback onPressed}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: darkGreen,
            border: Border.all(color: green, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: green, size: 22),
        ),
      ),
    );
  }

  void _toggleShuffle() {
    if (!mounted) {
      return;
    }

    setState(() {
      isShuffle = !isShuffle;

      if (!isShuffle) {
        _shuffleHistory.clear();
        _shuffleHistoryPosition = -1;
      } else {
        _shuffleHistory
          ..clear()
          ..add(currentSongIndex);

        _shuffleHistoryPosition = 0;
      }
    });
  }

  void _toggleRepeat() {
    if (!mounted) {
      return;
    }

    setState(() {
      switch (repeatMode) {
        case RepeatMode.off:
          repeatMode = RepeatMode.all;
          break;

        case RepeatMode.all:
          repeatMode = RepeatMode.one;
          break;

        case RepeatMode.one:
          repeatMode = RepeatMode.off;
          break;
      }
    });
  }

    // ============================================================
  // SEEK
  // ============================================================

  Future<void> _seek(Duration newPosition) async {
    if (audioPlayer == null) {
      return;
    }

    await audioPlayer!.seek(newPosition);

    if (!mounted) {
      return;
    }

    setState(() {
      position = newPosition;
    });
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    widget.palette?.removeListener(_onPaletteChanged);

    _playlistSearchController.dispose();

    final lastPosition = position;

    if (lastPosition.inMilliseconds > 0) {
      musicService.saveLastPositionMs(lastPosition.inMilliseconds);
    }

    _sleepTimer?.cancel();

    _sleepTicker?.cancel();

    _playingSubscription?.cancel();

    _positionSubscription?.cancel();

    _processingStateSubscription?.cancel();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final song = currentSong;

    if (song == null) {
      return _buildEmptyState();
    }

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final player = isLandscape
        ? _buildLandscapePlayer(song)
        : _buildPlayer(song);

    return Stack(
      children: [
        player,
        if (_fullscreen) _buildFullscreen(song),
      ],
    );
  }

  // ============================================================
  // PLAYER HORIZONTAL
  // ============================================================

  Widget _buildLandscapePlayer(Song song) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Responsivo, mas com limites para não transformar o player
          // num "outdoor" em tablets grandes.
          final horizontalPadding =
              (constraints.maxWidth * 0.018).clamp(14.0, 28.0);
          final verticalPadding =
              (constraints.maxHeight * 0.018).clamp(6.0, 14.0);

          final availableHeight =
              constraints.maxHeight - (verticalPadding * 2);

          final coverSize = (availableHeight * 0.56)
              .clamp(170.0, 270.0);

          final leftWidth =
              (constraints.maxWidth * 0.37).clamp(300.0, 560.0);

          final controlSize =
              (constraints.maxHeight * 0.055).clamp(34.0, 42.0);

          final playSize =
              (constraints.maxHeight * 0.095).clamp(62.0, 72.0);

          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // =====================================================
                // LADO DA CAPA
                // =====================================================
                SizedBox(
                  width: leftWidth,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _albumCover(
                        size: coverSize,
                        song: song,
                        active: green,
                        showAction: true,
                        onTap: _toggleFullscreen,
                      ),

                      const SizedBox(height: 12),

                      // MÚSICAS / PLAYLIST / TEMA ficam ligados à capa.
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _folderButton(compact: true),
                          const SizedBox(width: 8),
                          _playlistButton(compact: true),
                          const SizedBox(width: 8),
                          _themeButton(compact: true),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 18),

                // =====================================================
                // CONTROLOS
                // =====================================================
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'TSUKI PLAYER',
                            style: TextStyle(
                              fontFamily: 'Minecraftia',
                              color: green,
                              fontSize: 18,
                              letterSpacing: 1,
                            ),
                          ),
                          Row(
                            children: [
                              RetroEqualizer(
                                playing: isPlaying,
                                maxHeight: 10,
                                spacing: 2,
                                color: green,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                isPlaying ? 'A TOCAR AGORA' : 'EM PAUSA',
                                style: TextStyle(
                                  fontFamily: 'Minecraftia',
                                  color: green,
                                  fontSize: 8,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const Spacer(flex: 2),

                      // TÍTULO / ARTISTA
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          children: [
                            RetroMarquee(
                              text: song.title,
                              active: isPlaying,
                              style: TextStyle(
                                fontFamily: 'Minecraftia',
                                color: green,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 5),
                            RetroMarquee(
                              text: song.artist,
                              active: isPlaying,
                              style: TextStyle(
                                fontFamily: 'Minecraftia',
                                color: green.withAlpha(190),
                                fontSize: 8,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // PLAY / ANTERIOR / PRÓXIMA
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _controlButton(
                            icon: Icons.skip_previous,
                            size: controlSize,
                            onPressed: _previousSong,
                          ),
                          SizedBox(width: controlSize * 0.55),
                          Container(
                            width: playSize,
                            height: playSize,
                            decoration: BoxDecoration(
                              color: isPlaying ? green : Colors.black,
                              border: Border.all(color: green, width: 2),
                              borderRadius: BorderRadius.circular(13),
                              boxShadow: isPlaying
                                  ? [
                                      BoxShadow(
                                        color: green.withAlpha(45),
                                        blurRadius: 14,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: IconButton(
                              onPressed: _togglePlay,
                              icon: Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow,
                                color: isPlaying ? Colors.black : green,
                                size: (playSize * 0.55).clamp(34.0, 40.0),
                              ),
                            ),
                          ),
                          SizedBox(width: controlSize * 0.55),
                          _controlButton(
                            icon: Icons.skip_next,
                            size: controlSize,
                            onPressed: _nextSong,
                          ),
                        ],
                      ),

                      const SizedBox(height: 3),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: _toggleShuffle,
                            splashRadius: 20,
                            icon: Icon(
                              Icons.shuffle,
                              size: 20,
                              color: isShuffle ? green : green.withAlpha(85),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: _toggleRepeat,
                            splashRadius: 20,
                            icon: Icon(
                              repeatMode == RepeatMode.one
                                  ? Icons.repeat_one
                                  : Icons.repeat,
                              size: 20,
                              color: repeatMode != RepeatMode.off
                                  ? green
                                  : green.withAlpha(85),
                            ),
                          ),
                          const SizedBox(width: 4),
                          _sleepTimerButton(iconSize: 20, splashRadius: 20),
                        ],
                      ),

                      const SizedBox(height: 3),

                      RetroVolumeControl(
                        volume: _volume,
                        onChanged: _volumeChanged,
                        onChangeEnd: _volumeChangeEnd,
                        color: green,
                      ),

                      const Spacer(flex: 2),

                      // SEEKBAR
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: RetroSeekBar(
                          position: position,
                          duration: duration,
                          onSeek: _seek,
                          labelWidth: 48,
                          barHeight: 26,
                          color: green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_note, color: green, size: 58),

          const SizedBox(height: 18),

          Text(
            'TSUKI PLAYER',
            style: TextStyle(
              fontFamily: 'Minecraftia',
              color: green,
              fontSize: 20,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            'NENHUMA MÚSICA',
            style: TextStyle(
              fontFamily: 'Minecraftia',
              color: green,
              fontSize: 11,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            isLoading ? 'A PROCURAR MÚSICAS...' : 'ESCOLHE UMA PASTA',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Minecraftia',
              color: green,
              fontSize: 8,
            ),
          ),

          const SizedBox(height: 24),

          _folderButton(),
        ],
      ),
    );
  }

  // ============================================================
  // PLAYER
  // ============================================================

  Widget _buildPlayer(Song song) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        // Cresce com a tela, mas nunca fica exagerada.
        final heightFactor = (height / 760).clamp(0.82, 1.0);
        final coverSize = (width * 0.48 * heightFactor).clamp(165.0, 230.0);

        final playSize = (width * 0.18).clamp(66.0, 74.0);
        final sideControlSize = (width * 0.105).clamp(38.0, 42.0);

        return SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                const SizedBox(height: 7),

                // ==================================================
                // HEADER
                // ==================================================
                Text(
                  'TSUKI PLAYER',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Minecraftia',
                    color: green,
                    fontSize: 20,
                    letterSpacing: 1,
                  ),
                ),

                const SizedBox(height: 5),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RetroEqualizer(
                      playing: isPlaying,
                      maxHeight: 10,
                      spacing: 2,
                      color: green,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      isPlaying ? 'A TOCAR AGORA' : 'EM PAUSA',
                      style: TextStyle(
                        fontFamily: 'Minecraftia',
                        color: green,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),

                // ==================================================
                // BLOCO PRINCIPAL
                // ==================================================
                const Spacer(flex: 1),

                _albumCover(
                  size: coverSize,
                  song: song,
                  active: green,
                  showAction: true,
                  onTap: _toggleFullscreen,
                  iconSize: 65,
                ),

                const SizedBox(height: 11),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    children: [
                      RetroMarquee(
                        text: song.title,
                        active: isPlaying,
                        style: TextStyle(
                          fontFamily: 'Minecraftia',
                          color: green,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 5),
                      RetroMarquee(
                        text: song.artist,
                        active: isPlaying,
                        style: TextStyle(
                          fontFamily: 'Minecraftia',
                          color: green.withAlpha(190),
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // ==================================================
                // CONTROLOS
                // ==================================================
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _controlButton(
                      icon: Icons.skip_previous,
                      size: sideControlSize,
                      onPressed: _previousSong,
                    ),
                    SizedBox(width: width * 0.055),
                    Container(
                      width: playSize,
                      height: playSize,
                      decoration: BoxDecoration(
                        color: isPlaying ? green : Colors.black,
                        border: Border.all(color: green, width: 2),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: isPlaying
                            ? [
                                BoxShadow(
                                  color: green.withAlpha(45),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: IconButton(
                        onPressed: _togglePlay,
                        icon: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: isPlaying ? Colors.black : green,
                          size: (playSize * 0.55).clamp(36.0, 41.0),
                        ),
                      ),
                    ),
                    SizedBox(width: width * 0.055),
                    _controlButton(
                      icon: Icons.skip_next,
                      size: sideControlSize,
                      onPressed: _nextSong,
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // ==================================================
                // SEEKBAR
                // ==================================================
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: RetroSeekBar(
                    position: position,
                    duration: duration,
                    onSeek: _seek,
                    labelWidth: 54,
                    barHeight: 28,
                    color: green,
                  ),
                ),

                const SizedBox(height: 6),

                // ==================================================
                // ALEATÓRIO + REPETIR + TIMER
                // ==================================================
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _toggleShuffle,
                      tooltip: 'Aleatório',
                      splashRadius: 22,
                      icon: Icon(
                        Icons.shuffle,
                        size: 21,
                        color: isShuffle ? green : green.withAlpha(85),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _toggleRepeat,
                      tooltip: repeatMode == RepeatMode.one
                          ? 'Repetir música'
                          : repeatMode == RepeatMode.all
                              ? 'Repetir playlist'
                              : 'Repetição desligada',
                      splashRadius: 22,
                      icon: Icon(
                        repeatMode == RepeatMode.one
                            ? Icons.repeat_one
                            : Icons.repeat,
                        size: 21,
                        color: repeatMode != RepeatMode.off
                            ? green
                            : green.withAlpha(85),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _sleepTimerButton(),
                  ],
                ),

                const SizedBox(height: 2),

                RetroVolumeControl(
                  volume: _volume,
                  onChanged: _volumeChanged,
                  onChangeEnd: _volumeChangeEnd,
                  color: green,
                ),

                if (isLoading)
                  Padding(
                    padding: EdgeInsets.only(top: 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: green,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'A CARREGAR...',
                          style: TextStyle(
                            fontFamily: 'Minecraftia',
                            color: green,
                            fontSize: 7,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 5),

                // ==================================================
                // BOTÕES INFERIORES
                // ==================================================
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _folderButton(compact: true),
                    const SizedBox(width: 7),
                    _playlistButton(compact: true),
                    const SizedBox(width: 7),
                    _themeButton(compact: true),
                  ],
                ),

                const SizedBox(height: 7),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // PLAYLIST
  // ============================================================

void _showPlaylist() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final ownedSongs = _favoritesOnly
                ? songs.where((s) => _favorites.contains(s.file)).toList()
                : songs;

            final query = _playlistQuery.trim().toLowerCase();

            var visibleSongs = query.isEmpty
                ? ownedSongs
                : ownedSongs
                    .where((s) =>
                        s.title.toLowerCase().contains(query) ||
                        s.artist.toLowerCase().contains(query))
                    .toList();

            if (_playlistOrder == 'a') {
              visibleSongs = [...visibleSongs]
                ..sort((a, b) => a.title.toLowerCase().compareTo(
                    b.title.toLowerCase()));
            } else if (_playlistOrder == 'd') {
              visibleSongs = [...visibleSongs]
                ..sort((a, b) => a.duration.compareTo(b.duration));
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.76,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                border: Border(
                  top: BorderSide(color: green, width: 2),
                  left: BorderSide(color: green, width: 1),
                  right: BorderSide(color: green, width: 1),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),

                  // HANDLE
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: green,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // CABEÇALHO
                  Text(
                    'PLAYLIST',
                    style: TextStyle(
                      fontFamily: 'Minecraftia',
                      color: green,
                      fontSize: 17,
                      letterSpacing: 1,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.library_music, color: green, size: 14),

                      const SizedBox(width: 6),

                      Text(
                        '${visibleSongs.length} MÚSICAS · ${_playlistTotalDuration()}',
                        style: TextStyle(
                          fontFamily: 'Minecraftia',
                          color: green.withAlpha(160),
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // FILTRO: TODAS / FAVORITAS
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _playlistFilterChip(
                        label: 'TODAS',
                        active: !_favoritesOnly,
                        onPressed: () {
                          setSheetState(() {
                            _favoritesOnly = false;
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      _playlistFilterChip(
                        label: 'FAVORITAS ★',
                        active: _favoritesOnly,
                        onPressed: () {
                          setSheetState(() {
                            _favoritesOnly = true;
                          });
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // ORDENAÇÃO
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _playlistFilterChip(
                        label: 'Nº',
                        active: _playlistOrder == 'n',
                        onPressed: () {
                          setSheetState(() {
                            _playlistOrder = 'n';
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      _playlistFilterChip(
                        label: 'A-Z',
                        active: _playlistOrder == 'a',
                        onPressed: () {
                          setSheetState(() {
                            _playlistOrder = 'a';
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      _playlistFilterChip(
                        label: 'DURAÇÃO',
                        active: _playlistOrder == 'd',
                        onPressed: () {
                          setSheetState(() {
                            _playlistOrder = 'd';
                          });
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // BUSCA
                  Container(
                    height: 34,
                    margin: const EdgeInsets.symmetric(horizontal: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: _playlistQuery.isEmpty
                            ? green.withAlpha(70)
                            : green,
                        width: _playlistQuery.isEmpty ? 1 : 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 15, color: green),
                        const SizedBox(width: 7),
                        Expanded(
                          child: TextField(
                            controller: _playlistSearchController,
                            style: TextStyle(
                              fontFamily: 'Minecraftia',
                              color: green,
                              fontSize: 10,
                            ),
                            cursorColor: green,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              hintText: 'BUSCAR MÚSICA OU ARTISTA',
                              hintStyle: TextStyle(
                                fontFamily: 'Minecraftia',
                                color: green.withAlpha(80),
                                fontSize: 9,
                              ),
                            ),
                            onChanged: (value) {
                              setSheetState(() {
                                _playlistQuery = value;
                              });
                            },
                          ),
                        ),
                        if (_playlistQuery.isNotEmpty)
                          InkWell(
                            onTap: () {
                              _playlistSearchController.clear();

                              setSheetState(() {
                                _playlistQuery = '';
                              });
                            },
                            child: Icon(
                              Icons.close,
                              size: 15,
                              color: green.withAlpha(150),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // LISTA
                  Expanded(
                    child: visibleSongs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  query.isNotEmpty
                                      ? Icons.search_off
                                      : Icons.star_border,
                                  color: green.withAlpha(90),
                                  size: 34,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  query.isNotEmpty
                                      ? 'SEM RESULTADOS'
                                      : 'SEM FAVORITAS AINDA',
                                  style: TextStyle(
                                    fontFamily: 'Minecraftia',
                                    color: green.withAlpha(160),
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
                            itemCount: visibleSongs.length,
                            itemBuilder: (context, index) {
                              final song = visibleSongs[index];

                              final originalIndex = songs.indexOf(song);

                              final selected =
                                  originalIndex == currentSongIndex;

                              final isFavorite =
                                  _favorites.contains(song.file);

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(11),
                                    onTap: () {
                                      Navigator.of(context).pop();

                                      _selectSong(originalIndex);
                                    },
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 11,
                                        vertical: 11,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? darkGreen
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(11),
                                        border: Border.all(
                                          color: selected
                                              ? green
                                              : green.withAlpha(35),
                                          width: selected ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          // NÚMERO
                                          Container(
                                            width: 32,
                                            height: 32,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: selected
                                                  ? green.withAlpha(20)
                                                  : darkerGreen,
                                              borderRadius:
                                                  BorderRadius.circular(7),
                                            ),
                                            child: Text(
                                              selected
                                                  ? '▶'
                                                  : '${index + 1}'.padLeft(
                                                      2,
                                                      '0',
                                                    ),
                                              style: TextStyle(
                                                fontFamily: 'Minecraftia',
                                                color: green,
                                                fontSize: 8,
                                              ),
                                            ),
                                          ),

                                          const SizedBox(width: 11),

                                          // INFO
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  song.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontFamily: 'Minecraftia',
                                                    color: green,
                                                    fontSize: 9,
                                                    fontWeight: selected
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                  ),
                                                ),

                                                const SizedBox(height: 5),

                                                Text(
                                                  song.artist,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontFamily: 'Minecraftia',
                                                    color:
                                                        green.withAlpha(150),
                                                    fontSize: 7,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // FAVORITA
IconButton(
                                             onPressed: () async {
                                               await _toggleFavorite(song.file);

                                               setSheetState(() {});
                                             },
                                            splashRadius: 18,
                                            icon: Icon(
                                              isFavorite
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              size: 20,
                                              color: isFavorite
                                                  ? green
                                                  : green.withAlpha(70),
                                            ),
                                          ),

                                          // INDICADOR
                                          if (selected)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(
                                                left: 6,
                                              ),
                                              child: Icon(
                                                Icons.equalizer,
                                                color: green,
                                                size: 18,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _playlistFilterChip({
    required String label,
    required bool active,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? darkGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: active ? green : green.withAlpha(70),
              width: active ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Minecraftia',
              color: active ? green : green.withAlpha(150),
              fontSize: 8,
            ),
          ),
        ),
      ),
    );
  }

  String _playlistTotalDuration() {
    var total = Duration.zero;

    for (final song in songs) {
      final seconds = song.duration.inSeconds;

      if (seconds > 0) {
        total += Duration(seconds: seconds);
      }
    }

    if (total == Duration.zero) {
      return '--:--';
    }

    final m = total.inMinutes;
    final h = total.inHours;

    if (h > 0) {
      return '${h}h${(m % 60).toString().padLeft(2, '0')}m';
    }

    return '${m}m';
  }

  // ============================================================
  // BOTÃO PLAYLIST
  // ============================================================

  Widget _playlistButton({bool compact = false}) {
    return OutlinedButton.icon(
      onPressed: songs.isEmpty ? null : _showPlaylist,
      icon: const Icon(Icons.queue_music, size: 17),
      label: const Text(
        'PLAYLIST',
        style: TextStyle(fontFamily: 'Minecraftia', fontSize: 8),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: green,
        disabledForegroundColor: green.withAlpha(70),
        backgroundColor: Colors.black,
        side: BorderSide(color: green.withAlpha(180), width: 1.5),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 13 : 15,
          vertical: compact ? 8 : 11,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }

  // ============================================================
  // BOTÃO MÚSICAS
  // ============================================================

  Widget _folderButton({bool compact = false}) {
    return OutlinedButton.icon(
      onPressed: isLoading ? null : _chooseMusicFolder,
      icon: const Icon(Icons.folder_outlined, size: 17),
      label: const Text(
        'MÚSICAS',
        style: TextStyle(fontFamily: 'Minecraftia', fontSize: 8),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: green,
        disabledForegroundColor: green.withAlpha(70),
        backgroundColor: Colors.black,
        side: BorderSide(color: green.withAlpha(180), width: 1.5),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 13 : 15,
          vertical: compact ? 8 : 11,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }

  // ============================================================
  // BOTÃO TEMA
  // ============================================================

  Widget _themeButton({bool compact = false}) {
    return OutlinedButton.icon(
      onPressed: _showThemePicker,
      icon: const Icon(Icons.palette_outlined, size: 17),
      label: const Text(
        'TEMA',
        style: TextStyle(fontFamily: 'Minecraftia', fontSize: 8),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: green,
        backgroundColor: Colors.black,
        side: BorderSide(color: green.withAlpha(180), width: 1.5),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 13 : 15,
          vertical: compact ? 8 : 11,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }

  Widget _albumCover({
    required Song song,
    required double size,
    required bool showAction,
    VoidCallback? onTap,
    Color active = Colors.green,
    double iconSize = 60,
    int? cacheWidth,
    double frameRadius = 22,
    double outerPad = 4,
    double innerPad = 2,
    BoxShadow? shadow,
    double innerRadius = 8,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size + (outerPad * 2),
        height: size + (outerPad * 2),
        padding: EdgeInsets.all(outerPad),
        decoration: BoxDecoration(
          color: active,
          borderRadius: BorderRadius.circular(frameRadius),
          boxShadow: shadow != null
              ? [shadow]
              : [
                  BoxShadow(
                    color: active.withAlpha(35),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                padding: EdgeInsets.all(innerPad),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius:
                      BorderRadius.circular(frameRadius - innerRadius),
                ),
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(frameRadius - innerRadius - 3),
                  child: song.cover != null
                      ? Image.memory(
                          song.cover!,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                          cacheWidth: cacheWidth,
                        )
                      : Center(
                          child: Icon(
                            Icons.music_note,
                            color: active,
                            size: iconSize,
                          ),
                        ),
                ),
              ),
            ),
            if (showAction)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(170),
                    shape: BoxShape.circle,
                    border: Border.all(color: active.withAlpha(150)),
                  ),
                  child: Icon(
                    Icons.fullscreen,
                    color: active,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _toggleFullscreen() {
    final entering = !_fullscreen;

    setState(() {
      _fullscreen = entering;
    });

    SystemChrome.setEnabledSystemUIMode(
      entering ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  Widget _buildFullscreen(Song song) {
    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final landscape = constraints.maxWidth > constraints.maxHeight;

              final Widget cover = LayoutBuilder(
                builder: (context, c) {
                  final isLandscape = c.maxWidth > c.maxHeight;

                  final size = c.biggest.shortestSide * 0.72;

                  final horizontalSize =
                      c.maxWidth * (isLandscape ? 0.5 : 0.72);

                  final effectiveSize = isLandscape
                      ? horizontalSize.clamp(140.0, 300.0)
                      : size.clamp(200.0, 360.0);

                  return Center(
                    child: _albumCover(
                      size: effectiveSize,
                      song: song,
                      active: green,
                      showAction: false,
                      onTap: _toggleFullscreen,
                      iconSize: 78,
                      cacheWidth: 1024,
                      frameRadius: 28,
                      outerPad: 6,
                      innerPad: 3,
                      innerRadius: 10,
                      shadow: BoxShadow(
                        color: green.withAlpha(60),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ),
                  );
                },
              );

              final details = _fullscreenPanel(
                song: song,
                compact: landscape,
              );

              final Widget body;

              if (landscape) {
                // Duas metades: capa à esquerda, controlos à direita.
                body = Row(
                  children: [
                    Expanded(child: cover),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: details,
                        ),
                      ),
                    ),
                  ],
                );
              } else {
                body = Column(
                  children: [
                    Expanded(child: cover),
                    details,
                  ],
                );
              }

              return Stack(
                children: [
                  body,
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      onPressed: _toggleFullscreen,
                      tooltip: 'Sair da tela cheia',
                      splashRadius: 20,
                      icon: Icon(
                        Icons.fullscreen_exit,
                        color: green,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _fullscreenPanel({
    required Song song,
    required bool compact,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 18,
          ),
          child: Column(
            children: [
              RetroMarquee(
                text: song.title,
                active: isPlaying,
                style: TextStyle(
                  fontFamily: 'Minecraftia',
                  color: green,
                  fontSize: compact ? 14 : 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Minecraftia',
                  color: green.withAlpha(150),
                  fontSize: compact ? 9 : 10,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: compact ? 10 : 12),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: RetroSeekBar(
            position: position,
            duration: duration,
            onSeek: _seek,
            color: green,
            labelWidth: 52,
            barHeight: compact ? 18 : 24,
          ),
        ),

        SizedBox(height: compact ? 10 : 14),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _previousSong,
              splashRadius: 26,
              iconSize: compact ? 26 : 30,
              icon: Icon(Icons.skip_previous, color: green),
            ),
            const SizedBox(width: 22),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: green, width: 2),
              ),
              child: IconButton(
                onPressed: _togglePlay,
                splashRadius: 34,
                iconSize: compact ? 40 : 46,
                padding: const EdgeInsets.all(16),
                icon: Icon(
                  isPlaying ? Icons.pause_circle : Icons.play_circle,
                  color: green,
                ),
              ),
            ),
            const SizedBox(width: 22),
            IconButton(
              onPressed: _nextSong,
              splashRadius: 26,
              iconSize: compact ? 26 : 30,
              icon: Icon(Icons.skip_next, color: green),
            ),
          ],
        ),

        SizedBox(height: compact ? 6 : 18),
      ],
    );
  }

  static const List<String> _themeNames = ['VERDE', 'ÂMBAR', 'CIANO', 'MAGENTA'];

  void _showThemePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(
              top: BorderSide(color: green, width: 2),
              left: BorderSide(color: green, width: 1),
              right: BorderSide(color: green, width: 1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),

              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: green,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'TEMA DE COR',
                style: TextStyle(
                  fontFamily: 'Minecraftia',
                  color: green,
                  fontSize: 15,
                  letterSpacing: 1,
                ),
              ),

              const SizedBox(height: 14),

              for (var i = 0; i < RetroColors.all.length; i++)
                _themeOptionTile(index: i),

              const SizedBox(height: 18),
            ],
          ),
        );
      },
    );
  }

  Widget _themeOptionTile({required int index}) {
    final palette = RetroColors.all[index];

    final selected = _palette == palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () {
            Navigator.of(context).pop();

            _applyTheme(index);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: selected ? palette.dark : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected ? palette.primary : palette.primary.withAlpha(70),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: palette.primary,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: palette.primary.withAlpha(120),
                      width: 1,
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    _themeNames[index],
                    style: const TextStyle(
                      fontFamily: 'Minecraftia',
                      color: Colors.white,
                      fontSize: 9,
                    ),
                  ),
                ),

                if (selected)
                  Icon(Icons.check_circle, color: palette.primary, size: 15),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _applyTheme(int index) async {
    final palette = RetroColors.all[index];

    setState(() {
      _palette = palette;
    });

    widget.palette?.value = palette;

    await musicService.saveThemeIndex(index);
  }

  // ============================================================
  // CONTROLO
  // ============================================================

  Widget _controlButton({
    required IconData icon,
    required double size,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      splashRadius: 28,
      icon: Icon(icon, color: green, size: size),
    );
  }
}
