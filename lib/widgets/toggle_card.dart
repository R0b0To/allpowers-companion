import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tappable card representing a single outlet (USB / AC / DC) with an
/// active/disabled visual state.
class ToggleCard extends StatelessWidget {
  const ToggleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.activeLabel,
    required this.disabledLabel,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String activeLabel;
  final String disabledLabel;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: isActive ? activeColor.withOpacity(0.08) : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isActive ? activeColor : AppColors.border, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: isActive ? activeColor : Colors.grey[600]),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                isActive ? activeLabel : disabledLabel,
                style: TextStyle(fontSize: 10, color: isActive ? activeColor : Colors.grey[500]),
              ),
              const SizedBox(height: 12),
              Container(
                width: 28,
                height: 14,
                decoration: BoxDecoration(
                  color: isActive ? activeColor.withOpacity(0.3) : AppColors.border,
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: isActive ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isActive ? activeColor : Colors.grey[500],
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}