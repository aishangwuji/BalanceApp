import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/provider.dart';

class ProviderLogo extends StatelessWidget {
  const ProviderLogo({
    super.key,
    required this.providerId,
    this.size = 44,
    this.radius = 14,
  });

  final String providerId;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final ProviderDefinition? def = findProvider(providerId);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.16),
      decoration: BoxDecoration(
        color: c.iconTile,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.borderSoft),
      ),
      child: def == null
          ? Icon(Icons.hub_outlined, color: c.accent, size: size * 0.48)
          : Image.asset(
              def.iconAsset,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  def.name.characters.first,
                  style: TextStyle(
                    color: c.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: size * 0.4,
                  ),
                ),
              ),
            ),
    );
  }
}
