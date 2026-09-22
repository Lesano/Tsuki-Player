String formatDuration(Duration time) {
  final hours = time.inHours;

  final minutes = time.inMinutes.remainder(60).toString().padLeft(2, '0');

  final seconds = time.inSeconds.remainder(60).toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }

  return '$minutes:$seconds';
}