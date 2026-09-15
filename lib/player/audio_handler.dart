import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class TsukiAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();

  // Callbacks para a playlist do PlayerScreen.
  Future<void> Function()? onNextSong;
  Future<void> Function()? onPreviousSong;

  TsukiAudioHandler() {
    player.playbackEventStream.listen((event) {
      playbackState.add(
        PlaybackState(
          controls: [
            MediaControl.skipToPrevious,

            player.playing ? MediaControl.pause : MediaControl.play,

            MediaControl.skipToNext,
          ],

          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },

          androidCompactActionIndices: const [0, 1, 2],

          processingState: _getProcessingState(event.processingState),

          playing: player.playing,

          updatePosition: event.updatePosition,

          bufferedPosition: event.bufferedPosition,

          speed: player.speed,
        ),
      );
    });
  }

  // ============================================================
  // STREAMS
  // ============================================================

  Stream<bool> get playingStream => player.playingStream;

  Stream<Duration> get positionStream => player.positionStream;

  // NOVO:
  // Permite ao PlayerScreen saber quando
  // a música terminou.
  Stream<ProcessingState> get processingStateStream =>
      player.processingStateStream;

  bool get playing => player.playing;

  Duration get position => player.position;

  Duration? get duration => player.duration;

  // ============================================================
  // PROCESSING STATE
  // ============================================================

  AudioProcessingState _getProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;

      case ProcessingState.loading:
        return AudioProcessingState.loading;

      case ProcessingState.buffering:
        return AudioProcessingState.buffering;

      case ProcessingState.ready:
        return AudioProcessingState.ready;

      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  // ============================================================
  // ÁUDIO
  // ============================================================

  Future<void> setFilePath(String path) async {
    await player.setFilePath(path);
  }

  // ============================================================
  // PLAY
  // ============================================================

  @override
  Future<void> play() async {
    await player.play();
  }

  // ============================================================
  // PAUSE
  // ============================================================

  @override
  Future<void> pause() async {
    await player.pause();
  }

  // ============================================================
  // STOP
  // ============================================================

  @override
  Future<void> stop() async {
    await player.stop();
  }

  // ============================================================
  // SEEK
  // ============================================================

  @override
  Future<void> seek(Duration position) async {
    await player.seek(position);
  }

  // ============================================================
  // PRÓXIMA
  // ============================================================

  @override
  Future<void> skipToNext() async {
    final callback = onNextSong;

    if (callback != null) {
      await callback();
    }
  }

  // ============================================================
  // ANTERIOR
  // ============================================================

  @override
  Future<void> skipToPrevious() async {
    final callback = onPreviousSong;

    if (callback != null) {
      await callback();
    }
  }

  // ============================================================
  // GUARDAR CAPA
  // ============================================================

  Future<String?> _saveArtwork(Uint8List? artwork, String file) async {
    if (artwork == null || artwork.isEmpty) {
      return null;
    }

    try {
      final directory = await getTemporaryDirectory();

      // Cria um nome único baseado no caminho da música
      final id = base64Url.encode(utf8.encode(file)).replaceAll('=', '');

      final artworkFile = File('${directory.path}/tsuki_artwork_$id.jpg');

      await artworkFile.writeAsBytes(artwork, flush: true);

      return artworkFile.path;
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // MEDIA ITEM
  // ============================================================

  Future<void> setCurrentMediaItem({
    required String file,
    required String title,
    required String artist,
    Uint8List? artwork,
  }) async {
    String? artworkPath;

    // A capa nunca deve impedir
    // a música de carregar.
    try {
      artworkPath = await _saveArtwork(artwork, file);
    } catch (e) {
      // Artwork failures must not prevent playback metadata from updating.
    }

    mediaItem.add(
      MediaItem(
        id: file,
        title: title,
        artist: artist,
        duration: player.duration,
        artUri: artworkPath != null ? Uri.file(artworkPath) : null,
      ),
    );
  }

  // ============================================================
  // TASK REMOVED
  // ============================================================

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  void dispose() {
    player.dispose();
  }
}
