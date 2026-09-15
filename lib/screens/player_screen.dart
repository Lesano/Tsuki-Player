import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../main.dart';
import '../models/song.dart';
import '../player/audio_handler.dart';
import '../services/music_service.dart';

enum RepeatMode {
  off,
  all,
  one,
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final MusicService musicService = MusicService();

  TsukiAudioHandler? audioPlayer;

  List<Song> songs = [];

  int currentSongIndex = 0;

  bool isLoading = true;
  bool isPlaying = false;

  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<ProcessingState>? _processingStateSubscription;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  static const Color green = Color(0xFF4CAF50);
  static const Color darkGreen = Color(0xFF12351A);
  static const Color darkerGreen = Color(0xFF071B0C);

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

    _initialize();
  }

  // ============================================================
  // INICIALIZAÇÃO
  // ============================================================

  Future<void> _initialize() async {
    await _loadSavedMusic();

    await _connectAudioHandler();
  }

  // ============================================================
  // AUDIO HANDLER
  // ============================================================

  Future<void> _connectAudioHandler() async {
    // Espera pelo AudioService por no máximo 5 segundos.
    for (int i = 0; i < 100; i++) {
      if (audioHandler != null) {
        break;
      }

      await Future.delayed(const Duration(milliseconds: 50));

      if (!mounted) {
        return;
      }
    }

    if (!mounted) {
      return;
    }

    // Verifica se o AudioHandler existe.
    if (audioHandler == null) {
      return;
    }

    // ==========================================================
    // LIGA O HANDLER
    // ==========================================================

    audioPlayer = audioHandler;

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
    // CARREGAR MÚSICA ATUAL
    // ==========================================================

    if (songs.isNotEmpty) {
      await _loadCurrentSong();
    }
  }

  // ============================================================
  // BIBLIOTECA
  // ============================================================

  Future<void> _loadSavedMusic() async {

    final loadedSongs = await musicService.loadSavedMusic();

    if (!mounted) {
      return;
    }

    setState(() {
      songs = loadedSongs;
      currentSongIndex = 0;
      isLoading = false;
    });


    for (int i = 0; i < songs.length; i++) {
    }

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

    final loadedSongs = await musicService.chooseMusicFolder();

    if (!mounted) {
      return;
    }

    setState(() {
      songs = loadedSongs;
      currentSongIndex = 0;
      isLoading = false;
    });

    if (songs.isNotEmpty && audioPlayer != null) {
      await _loadCurrentSong();
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

      // ========================================================
      // METADATA + CAPA
      // ========================================================

      // Se já preparámos esta música, reutiliza os dados.
      // Isto elimina o processamento repetido ao trocar de faixa.
      final preparedSong =
          _preparedSongs[song.file] ??
          await musicService.prepareSong(song);

      _preparedSongs[song.file] = preparedSong;

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
        position = Duration.zero;
      });

    } catch (e) {
      // Ignore individual track loading failures and keep the player usable.
    }
  }

  // ============================================================
  // SELECIONAR MÚSICA
  // ============================================================

  Future<void> _selectSong(int index) async {
    if (index < 0 || index >= songs.length) {
      return;
    }

    Navigator.of(context).pop();

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
        await audioPlayer!.play();
      }
    } catch (e) {
      // Ignore playback errors; the audio handler remains available.
    }
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

    final wasPlaying = audioPlayer!.playing;

    if (mounted) {
      setState(() {
        currentSongIndex = nextIndex;
      });
    }

    await _loadCurrentSong();

    // Próxima faixa toca automaticamente.
    // Se foi uma troca manual, também mantém o comportamento atual.
    if (automatic || wasPlaying || !automatic) {
      await audioPlayer!.play();
    }
  }

  // ============================================================
  // MODOS
  // ============================================================

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
  // FORMATAR TEMPO
  // ============================================================

  String _formatTime(Duration time) {
    final minutes = time.inMinutes.remainder(60).toString().padLeft(2, '0');

    final seconds = time.inSeconds.remainder(60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
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

    return isLandscape
        ? _buildLandscapePlayer(song)
        : _buildPlayer(song);
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
                      Container(
                        width: coverSize,
                        height: coverSize,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: green,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: green.withAlpha(35),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: song.cover != null
                                ? Image.memory(
                                    song.cover!,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.medium,
                                  )
                                : const Center(
                                    child: Icon(
                                      Icons.music_note,
                                      color: green,
                                      size: 60,
                                    ),
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // MÚSICAS / PLAYLIST ficam ligados à capa.
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _folderButton(compact: true),
                          const SizedBox(width: 10),
                          _playlistButton(compact: true),
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
                          const Text(
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
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: isPlaying ? green : darkGreen,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                isPlaying ? 'A TOCAR AGORA' : 'EM PAUSA',
                                style: const TextStyle(
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
                            Text(
                              song.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Minecraftia',
                                color: green,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              song.artist,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                        ],
                      ),

                      const Spacer(flex: 2),

                      // SEEKBAR
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 48,
                              child: Text(
                                _formatTime(position),
                                style: const TextStyle(
                                  fontFamily: 'Minecraftia',
                                  color: green,
                                  fontSize: 8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, barConstraints) {
                                  final total = duration.inMilliseconds;
                                  final progress = total > 0
                                      ? (position.inMilliseconds / total)
                                          .clamp(0.0, 1.0)
                                      : 0.0;

                                  void seekFromOffset(double dx) {
                                    if (total <= 0 ||
                                        barConstraints.maxWidth <= 0) {
                                      return;
                                    }

                                    final percentage =
                                        (dx / barConstraints.maxWidth)
                                            .clamp(0.0, 1.0);

                                    _seek(
                                      Duration(
                                        milliseconds:
                                            (total * percentage).round(),
                                      ),
                                    );
                                  }

                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapDown: (details) => seekFromOffset(
                                      details.localPosition.dx,
                                    ),
                                    onHorizontalDragStart: (details) =>
                                        seekFromOffset(
                                      details.localPosition.dx,
                                    ),
                                    onHorizontalDragUpdate: (details) =>
                                        seekFromOffset(
                                      details.localPosition.dx,
                                    ),
                                    child: Container(
                                      height: 26,
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        border: Border.all(
                                          color: green,
                                          width: 3,
                                        ),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: LayoutBuilder(
                                        builder: (context, inner) {
                                          return Stack(
                                            clipBehavior: Clip.hardEdge,
                                            children: [
                                              Positioned(
                                                left: 0,
                                                top: 0,
                                                bottom: 0,
                                                width: inner.maxWidth * progress,
                                                child: Container(color: green),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 48,
                              child: Text(
                                _formatTime(duration),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontFamily: 'Minecraftia',
                                  color: green,
                                  fontSize: 8,
                                ),
                              ),
                            ),
                          ],
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
          const Icon(Icons.music_note, color: green, size: 58),

          const SizedBox(height: 18),

          const Text(
            'TSUKI PLAYER',
            style: TextStyle(
              fontFamily: 'Minecraftia',
              color: green,
              fontSize: 20,
            ),
          ),

          const SizedBox(height: 10),

          const Text(
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
            style: const TextStyle(
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
                const Text(
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
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isPlaying ? green : darkGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      isPlaying ? 'A TOCAR AGORA' : 'EM PAUSA',
                      style: const TextStyle(
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

                Container(
                  width: coverSize + 14,
                  height: coverSize + 14,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: green,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: green.withAlpha(35),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: song.cover != null
                          ? Image.memory(
                              song.cover!,
                              width: coverSize,
                              height: coverSize,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.medium,
                            )
                          : const Center(
                              child: Icon(
                                Icons.music_note,
                                color: green,
                                size: 65,
                              ),
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 11),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    children: [
                      Text(
                        song.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Minecraftia',
                          color: green,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        song.artist,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 54,
                        child: Text(
                          _formatTime(position),
                          style: const TextStyle(
                            fontFamily: 'Minecraftia',
                            color: green,
                            fontSize: 8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, barConstraints) {
                            final total = duration.inMilliseconds;
                            final progress = total > 0
                                ? (position.inMilliseconds / total)
                                    .clamp(0.0, 1.0)
                                : 0.0;

                            void seekFromOffset(double dx) {
                              if (total <= 0 ||
                                  barConstraints.maxWidth <= 0) {
                                return;
                              }

                              final percentage =
                                  (dx / barConstraints.maxWidth)
                                      .clamp(0.0, 1.0);

                              _seek(
                                Duration(
                                  milliseconds:
                                      (total * percentage).round(),
                                ),
                              );
                            }

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (details) => seekFromOffset(
                                details.localPosition.dx,
                              ),
                              onHorizontalDragStart: (details) =>
                                  seekFromOffset(
                                details.localPosition.dx,
                              ),
                              onHorizontalDragUpdate: (details) =>
                                  seekFromOffset(
                                details.localPosition.dx,
                              ),
                              child: Container(
                                height: 28,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  border: Border.all(
                                    color: green,
                                    width: 3,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: LayoutBuilder(
                                  builder: (context, inner) {
                                    return Stack(
                                      clipBehavior: Clip.hardEdge,
                                      children: [
                                        Positioned(
                                          left: 0,
                                          top: 0,
                                          bottom: 0,
                                          width: inner.maxWidth * progress,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: green,
                                              borderRadius:
                                                  BorderRadius.circular(1),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 54,
                        child: Text(
                          _formatTime(duration),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontFamily: 'Minecraftia',
                            color: green,
                            fontSize: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 6),

                // ==================================================
                // ALEATÓRIO + REPETIR
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
                  ],
                ),

                if (isLoading)
                  const Padding(
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
                    const SizedBox(width: 9),
                    _playlistButton(compact: true),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.76,
          decoration: const BoxDecoration(
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
              const Text(
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
                  const Icon(Icons.library_music, color: green, size: 14),

                  const SizedBox(width: 6),

                  Text(
                    '${songs.length} MÚSICAS',
                    style: TextStyle(
                      fontFamily: 'Minecraftia',
                      color: green.withAlpha(160),
                      fontSize: 8,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // LISTA
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];

                    final selected = index == currentSongIndex;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(11),
                          onTap: () {
                            _selectSong(index);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: selected ? darkGreen : Colors.transparent,
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: selected ? green : green.withAlpha(35),
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
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Text(
                                    selected
                                        ? '▶'
                                        : '${index + 1}'.padLeft(2, '0'),
                                    style: const TextStyle(
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
                                        overflow: TextOverflow.ellipsis,
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
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Minecraftia',
                                          color: green.withAlpha(150),
                                          fontSize: 7,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // INDICADOR
                                if (selected)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8),
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
