import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';

enum _TrendDirection { up, down, stable }

/// Carte statistique standard (icone + titre + valeur + tendance optionnelle
/// + mini-sparkline optionnelle), utilisee pour les KPI du tableau de bord
/// et de l'en-tete caisse. Purement presentationnel: [value] est deja
/// formatee par l'appelant, [trendPercent]/[sparklineData] sont de simples
/// nombres deja calcules cote appelant (aucun calcul metier ici).
class StatCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? accent;
  final double? width;

  /// Variation en % vs periode precedente (ex: 18.4 pour "+18.4%"). Null =
  /// pas de ligne de tendance affichee.
  final double? trendPercent;

  /// Texte de comparaison sous la tendance (ex: "Compare a hier"). Ignore si
  /// [trendPercent] est null.
  final String? comparisonLabel;

  /// Historique jour par jour pour la mini-courbe. Null ou < 2 points = pas
  /// de sparkline (on ne simule jamais un historique factice).
  final List<double>? sparklineData;

  const StatCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.trendPercent,
    this.comparisonLabel,
    this.sparklineData,
    this.accent,
    this.width,
  });

  @override
  State<StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<StatCard> {
  bool _hovered = false;

  _TrendDirection get _direction {
    final trend = widget.trendPercent;
    if (trend == null || trend.abs() < 0.05) {
      return _TrendDirection.stable;
    }
    return trend > 0 ? _TrendDirection.up : _TrendDirection.down;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = widget.accent ?? colorScheme.primary;
    final sparkline = widget.sparklineData;
    final hasSparkline = sparkline != null && sparkline.length >= 2;

    final card = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 8),
            child: child,
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: AppRadius.cardAll,
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: _hovered ? 0.08 : 0.05,
                ),
                blurRadius: _hovered ? 30 : 25,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          transform: _hovered
              ? Matrix4.translationValues(0.0, -2.0, 0.0)
              : Matrix4.identity(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(widget.icon, color: accent, size: 20),
                  ),
                  if (hasSparkline)
                    SizedBox(
                      width: 64,
                      height: 28,
                      child: CustomPaint(
                        painter: _SparklinePainter(
                          values: sparkline,
                          color: accent,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  widget.value,
                  key: ValueKey(widget.value),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (widget.trendPercent != null) ...[
                const SizedBox(height: 8),
                _TrendRow(
                  direction: _direction,
                  trendPercent: widget.trendPercent!,
                  comparisonLabel: widget.comparisonLabel,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return widget.width == null
        ? card
        : SizedBox(width: widget.width, child: card);
  }
}

class _TrendRow extends StatelessWidget {
  final _TrendDirection direction;
  final double trendPercent;
  final String? comparisonLabel;

  const _TrendRow({
    required this.direction,
    required this.trendPercent,
    required this.comparisonLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color color;
    final String glyph;
    switch (direction) {
      case _TrendDirection.up:
        color = AppColors.success;
        glyph = '▲';
        break;
      case _TrendDirection.down:
        color = AppColors.danger;
        glyph = '▼';
        break;
      case _TrendDirection.stable:
        color = AppColors.neutral;
        glyph = '▬';
        break;
    }
    final label = direction == _TrendDirection.stable
        ? 'Stable'
        : '${trendPercent > 0 ? '+' : ''}${trendPercent.toStringAsFixed(1)}%';

    return Row(
      children: [
        Text('$glyph $label', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        if (comparisonLabel != null) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              comparisonLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}

/// Mini-courbe (sparkline) native, sans dependance externe: normalise
/// [values] entre 0 et 1 et trace une ligne avec un leger remplissage
/// degrade en dessous, colore selon l'accent de la carte.
class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final range = (maxValue - minValue).abs() < 1e-9 ? 1.0 : maxValue - minValue;

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = size.width * (i / (values.length - 1));
      final normalized = (values[i] - minValue) / range;
      final y = size.height * (1 - normalized);
      points.add(Offset(x, y));
    }

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }

    final fillPath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
