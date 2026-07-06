import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import 'toggle_card.dart';

/// The row of USB / AC / DC [ToggleCard]s shown on both the local
/// [ControlTab] and the remote [MqttClientTab].
///
/// The two call sites need different *plumbing* — the local tab calls
/// [BleService] directly (already optimistic internally, via
/// `BleService._setSocket`), while the remote tab sends an RPC and tracks
/// its own per-outlet optimistic/pending state while waiting for a
/// response. Only the row of cards itself was actually duplicated, so only
/// that is extracted here: each caller resolves its own "what state should
/// this outlet currently show" and "what happens on tap" and passes the
/// result in, keeping the differing state-management logic where it
/// belongs instead of forcing it into a shared widget.
class OutletControlsRow extends StatelessWidget {
  const OutletControlsRow({
    super.key,
    required this.strings,
    required this.isUsbOn,
    required this.isAcOn,
    required this.isDcOn,
    required this.onToggleUsb,
    required this.onToggleAc,
    required this.onToggleDc,
  });

  final AppStrings strings;
  final bool isUsbOn;
  final bool isAcOn;
  final bool isDcOn;
  final VoidCallback onToggleUsb;
  final VoidCallback onToggleAc;
  final VoidCallback onToggleDc;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ToggleCard(
            icon: Icons.usb_rounded,
            title: strings.t('usb'),
            activeLabel: strings.t('active'),
            disabledLabel: strings.t('disabled'),
            isActive: isUsbOn,
            activeColor: AppColors.usb,
            onTap: onToggleUsb,
          ),
          const SizedBox(width: AppSpacing.sm),
          ToggleCard(
            icon: Icons.power_rounded,
            title: strings.t('ac'),
            activeLabel: strings.t('active'),
            disabledLabel: strings.t('disabled'),
            isActive: isAcOn,
            activeColor: AppColors.ac,
            onTap: onToggleAc,
          ),
          const SizedBox(width: AppSpacing.sm),
          ToggleCard(
            icon: Icons.cable_rounded,
            title: strings.t('dc'),
            activeLabel: strings.t('active'),
            disabledLabel: strings.t('disabled'),
            isActive: isDcOn,
            activeColor: AppColors.dc,
            onTap: onToggleDc,
          ),
        ],
      ),
    );
  }
}