import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';

/// En-tete de section standard (titre 22/700 + sous-titre optionnel 14),
/// remplace les Text(...headlineSmall...) ad hoc repetes sur chaque ecran.
class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.sectionTitle(context)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: AppTypography.small(context)),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
