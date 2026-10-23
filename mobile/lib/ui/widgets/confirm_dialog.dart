import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String message = '',
  String confirmText = '确认',
  String cancelText = '取消',
  bool danger = false,
}) async {
  final AppColors c = context.colors;
  final bool? result = await showDialog<bool>(
    context: context,
    barrierColor: c.overlayScrim,
    builder: (BuildContext context) {
      return Dialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: c.borderSoft),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.textTitle,
                ),
              ),
              if (message.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: c.textMuted,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: <Widget>[
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.fill,
                          foregroundColor: c.textPrimary,
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(cancelText),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              danger ? c.dangerText : c.accentSolid,
                          foregroundColor: c.accentContrast,
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(confirmText),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result == true;
}
