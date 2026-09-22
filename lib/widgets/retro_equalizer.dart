import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Barras de LED estilo "equalizador" retrô.
///
/// Cuando a música está a tocar, as barras animam no ritmo.
/// Quando está pausada, ficam paradas e escuras.
class RetroEqualizer extends StatefulWidget {
  const RetroEqualizer({
    super.key,
    required this.playing,
    this.color = const Color(0xFF4CAF50),
    this.barCount = 4,
    this.barWidth = 3,
    this.spacing = 2,
    this.maxHeight = 12,
  });

  final bool playing;

  final Color color;

  final int barCount;

  final double barWidth;

  final double spacing;

  final double maxHeight;

  @override
  State<RetroEqualizer> createState() => _RetroEqualizerState();
}

class _RetroEqualizerState extends State<RetroEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final List<double> _phases;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    // Fases diferentes deixam o movimento menos "em bloco".
    _phases = List.generate(widget.barCount, (i) => i * 1.7 + 0.3);

    if (widget.playing) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(RetroEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barColor = widget.playing
        ? widget.color
        : widget.color.withAlpha(90);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(widget.barCount, (i) {
            final wave = widget.playing
                ? (math.sin(_controller.value * math.pi * 2 + _phases[i]) +
                        1) /
                    2
                : 0.2;

            final height = 3 + wave * (widget.maxHeight - 3);

            return Padding(
              padding: EdgeInsets.only(left: widget.spacing),
              child: Container(
                width: widget.barWidth,
                height: height,
                color: barColor,
              ),
            );
          }),
        );
      },
    );
  }
}