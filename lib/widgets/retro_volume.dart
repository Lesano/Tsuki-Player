import 'package:flutter/material.dart';

/// Controle de volume compacto no estilo retro.
///
/// Live updates via [onChanged]; a aplicação final (e persistência)
/// deve ficar em [onChangeEnd].
class RetroVolumeControl extends StatelessWidget {
  const RetroVolumeControl({
    super.key,
    required this.volume,
    required this.onChanged,
    this.onChangeEnd,
    this.color = const Color(0xFF4CAF50),
    this.sliderWidth = 90,
  });

  final double volume;

  final ValueChanged<double> onChanged;

  final ValueChanged<double>? onChangeEnd;

  final Color color;

  final double sliderWidth;

  @override
  Widget build(BuildContext context) {
    final muted = volume <= 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          muted ? Icons.volume_off : Icons.volume_up,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: sliderWidth,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              activeTrackColor: color,
              inactiveTrackColor: color.withAlpha(90),
              thumbColor: muted ? color.withAlpha(90) : color,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              overlayColor: color.withAlpha(30),
            ),
            child: Slider(
              value: volume.clamp(0.0, 1.0).toDouble(),
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
      ],
    );
  }
}