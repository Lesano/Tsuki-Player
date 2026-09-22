import 'dart:typed_data';

class Song {
  final String title;
  final String artist;
  final String file;
  final Uint8List? cover;
  final Duration duration;

  Song({
    required this.title,
    required this.artist,
    required this.file,
    this.cover,
    this.duration = Duration.zero,
  });
}