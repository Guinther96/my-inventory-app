import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'custom_card.dart';

/// Carte statistique standard (icone + titre + valeur + variation
/// optionnelle), utilisee pour les KPI du tableau de bord et de l'en-tete
/// caisse. Remplace les cartes de stats ad hoc (ModernSummaryCard,
/// HeaderMetric) qui dupliquaient le meme visuel. Purement presentationnel:
/// [value] est deja formatee par l'appelant (aucun calcul ici).
class StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String? trend;
  final bool trendPositive;
  final Color accent;
  final double? width;

  const StatCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.trend,
    this.trendPositive = true,
    this.accent = AppColors.primary,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final card = CustomCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              value,
              key: ValueKey(value),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (trend != null) ...[
                const SizedBox(width: 6),
                Text(
                  trend!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: trendPositive ? AppColors.success : AppColors.danger,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    return width == null ? card : SizedBox(width: width, child: card);
  }
}
