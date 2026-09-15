String formatTime(double seconds) {
  int totalSeconds = seconds.toInt();

  int minutes = totalSeconds ~/ 60;
  int secs = totalSeconds % 60;

  return '$minutes:${secs.toString().padLeft(2, '0')}';
}
