import 'package:just_audio/just_audio.dart';

class AudioPlayerController {
  final AudioPlayer player = AudioPlayer();

  Future<void> load(String file) async {
    await player.setAsset(file);
  }

  Future<void> play() async {
    await player.play();
  }

  Future<void> pause() async {
    await player.pause();
  }

  Future<void> seek(Duration position) async {
    await player.seek(position);
  }

  void dispose() {
    player.dispose();
  }
}
