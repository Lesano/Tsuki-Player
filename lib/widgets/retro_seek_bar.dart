import 'package:flutter/material.dart';

import '../utils/format_time.dart';

class RetroSeekBar extends StatelessWidget {
  const RetroSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.color = const Color(0xFF4CAF50),
    this.labelWidth = 48,
    this.barHeight = 26,
  });

  final Duration position;
  final Duration duration;

  final ValueChanged<Duration> onSeek;

  final Color color;

  /// Largura dos rótulos de tempo (`m:ss`) à esquerda e à direita.
  final double labelWidth;

  /// Altura do retângulo da barra (exclui os rótulos).
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds;
    final progress = total > 0
        ? (position.inMilliseconds / total).clamp(0.0, 1.0)
        : 0.0;

    return Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            formatDuration(position),
            style: TextStyle(
              fontFamily: 'Minecraftia',
              color: color,
              fontSize: 8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, barConstraints) {
              void seekFromOffset(double dx) {
                if (total <= 0 || barConstraints.maxWidth <= 0) {
                  return;
                }

                final percentage = (dx / barConstraints.maxWidth).clamp(
                  0.0,
                  1.0,
                );

                onSeek(
                  Duration(
                    milliseconds: (total * percentage).round(),
                  ),
                );
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => seekFromOffset(
                  details.localPosition.dx,
                ),
                onHorizontalDragStart: (details) => seekFromOffset(
                  details.localPosition.dx,
                ),
                onHorizontalDragUpdate: (details) => seekFromOffset(
                  details.localPosition.dx,
                ),
                child: Container(
                  height: barHeight,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: color, width: 3),
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
                            child: Container(color: color),
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
          width: labelWidth,
          child: Text(
            formatDuration(duration),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: 'Minecraftia',
              color: color,
              fontSize: 8,
            ),
          ),
        ),
      ],
    );
  }
}