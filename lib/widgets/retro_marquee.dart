import 'package:flutter/material.dart';

/// Título/artista em estilo "ticker" de ecrã LCD.
///
/// Quando o texto é maior que a área disponível, faz scroll
/// automático da direita para a esquerda, começando pelo início
/// do texto e varrendo até sair por completo.
/// Quando não está ativo (ex.: pausado), fica estático com reticências.
class RetroMarquee extends StatefulWidget {
  const RetroMarquee({
    super.key,
    required this.text,
    required this.style,
    this.active = true,
    this.gap = 40,
  });

  final String text;

  final TextStyle style;

  /// Se `false`, o texto nunca faz scroll (fica estático).
  final bool active;

  /// Espaço extra mínimo percorrido depois do texto sair do ecrã.
  final double gap;

  @override
  State<RetroMarquee> createState() => _RetroMarqueeState();
}

class _RetroMarqueeState extends State<RetroMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Velocidade constante de deslocamento (píxeis por segundo).
  static const double _speed = 120;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didUpdateWidget(RetroMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.active) {
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
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();

    final textWidth = painter.width;

    return LayoutBuilder(
      builder: (context, constraints) {
        final areaWidth = constraints.maxWidth;

        if (areaWidth <= 0) {
          return const SizedBox.shrink();
        }

        // Texto cabe (ou está pausado): comportamento estático centrado.
        if (!widget.active || textWidth <= areaWidth) {
          return Text(
            widget.text,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        // Ticker: percorre do início até o texto sair por completo.
        final travel = textWidth + widget.gap;

        final durationMs =
            (travel / _speed * 1000).round().clamp(1000, 30000).toInt();

        if (_controller.duration?.inMilliseconds != durationMs) {
          _controller.duration = Duration(milliseconds: durationMs);
        }

        if (!_controller.isAnimating) {
          _controller.value = 0;
          _controller.repeat();
        }

        final x = -_controller.value * travel;

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(x, 0),
                child: child,
              );
            },
            child: Text(
              widget.text,
              maxLines: 1,
              softWrap: false,
              style: widget.style,
            ),
          ),
        );
      },
    );
  }
}