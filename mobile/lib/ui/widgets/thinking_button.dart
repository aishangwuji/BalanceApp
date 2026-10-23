import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/provider.dart';

class ThinkingButton extends StatelessWidget {
  const ThinkingButton({
    super.key,
    required this.enabled,
    required this.providerId,
    required this.modelId,
    required this.onToggle,
  });

  final bool enabled;
  final String providerId;
  final String modelId;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    if (!isThinkingSupported(providerId, modelId)) {
      return const SizedBox.shrink();
    }
    final AppColors c = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onToggle(!enabled),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: enabled ? c.accentSoft : c.fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled ? c.accentOutline : Colors.transparent,
            ),
          ),
          child: Text(
            '深度思考',
            style: TextStyle(
              fontSize: 13,
              fontWeight: enabled ? FontWeight.w500 : FontWeight.w400,
              color: enabled ? c.accent : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
