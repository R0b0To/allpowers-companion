import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/tapo_device.dart';
import '../services/tapo_device_service.dart';
import '../services/tapo_service.dart';
import '../theme/app_theme.dart';
import '../widgets/toggle_card.dart';

/// Lists all saved Tapo smart plugs, shows their live state, and lets the
/// user add, edit, or remove devices.
class DevicesTab extends StatelessWidget {
  const DevicesTab({
    super.key,
    required this.tapoDevices,
    required this.tapo,
    required this.strings,
  });

  final TapoDeviceService tapoDevices;
  final TapoService tapo;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tapoDevices,
      builder: (context, _) => SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final devices = tapoDevices.devices;

    return CustomScrollView(
      slivers: [
        // ── Header ──────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.t('tab_devices'),
                        style: AppTypography.displaySm,
                      ),
                    ),
                    IconButton(
                      onPressed: () => tapoDevices.refresh(),
                      tooltip: strings.t('devices_refresh'),
                      icon: const Icon(Icons.refresh_rounded,
                          color: AppColors.textTertiary),
                    ),
                    IconButton(
                      onPressed: () => _showAddEditSheet(context, null),
                      tooltip: strings.t('devices_add'),
                      icon: const Icon(Icons.add_rounded, color: AppColors.teal),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  strings.t('devices_description'),
                  style: AppTypography.bodyMd,
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),

        // ── Device list ──────────────────────────────────────────────────────
        if (devices.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyDevicesView(
              strings: strings,
              onAdd: () => _showAddEditSheet(context, null),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            sliver: SliverList.separated(
              itemCount: devices.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) => _DeviceCard(
                device: devices[i],
                strings: strings,
                onToggle: (on) => tapoDevices.setDeviceOn(devices[i].id, on),
                onEdit: () => _showAddEditSheet(context, devices[i]),
                onDelete: () => _confirmDelete(context, devices[i]),
              ),
            ),
          ),
      ],
    );
  }

  void _showAddEditSheet(BuildContext context, TapoDevice? existing) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DeviceFormSheet(
        existing: existing,
        tapo: tapo,
        strings: strings,
        onSave: (device) async {
          if (existing == null) {
            await tapoDevices.addDevice(device);
          } else {
            await tapoDevices.updateDevice(device);
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, TapoDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Remove "${device.name}"?',
          style: AppTypography.headingMd,
        ),
        content: Text(
          'This device will be removed from your list. Any automations '
          'referencing it will no longer work.',
          style: AppTypography.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.t('cancel'),
                style: AppTypography.headingSm
                    .copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Remove',
                style:
                    AppTypography.headingSm.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await tapoDevices.removeDevice(device.id);
    }
  }
}

// ── Device card ───────────────────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.strings,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final TapoDevice device;
  final AppStrings strings;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor =
        device.isOnline ? AppColors.success : AppColors.textDisabled;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.lgBR,
        border: Border.all(
          color: device.isOnline && device.isOn
              ? AppColors.warning.withValues(alpha:0.4)
              : theme.colorScheme.outline,
          width: device.isOnline && device.isOn ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.sm, 0),
            child: Row(
              children: [
                // Status dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.name, style: AppTypography.headingSm),
                      Text(
                        device.isOnline
                            ? (device.model.isNotEmpty
                                ? device.model
                                : device.ip)
                            : '${device.ip} · Offline',
                        style: AppTypography.bodySm,
                      ),
                    ],
                  ),
                ),
                // Edit button
                IconButton(
                  onPressed: onEdit,
                  icon: Icon(Icons.edit_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha:0.6)),
                ),
                // Delete button
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppColors.error.withValues(alpha:0.7)),
                ),
              ],
            ),
          ),

          // ── Toggle row ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: ToggleCard(
                    icon: Icons.power_rounded,
                    title: strings.t('plug_power'),
                    activeLabel: strings.t('active'),
                    disabledLabel: strings.t('disabled'),
                    isActive: device.isOnline && device.isOn,
                    activeColor: AppColors.warning,
                    enabled: device.isOnline,
                    onTap: () => onToggle(!device.isOn),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _InfoCard(device: device),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.device});
  final TapoDevice device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.lgBR,
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha:0.12),
                  borderRadius: AppRadius.smBR,
                ),
                child: const Icon(Icons.wifi_rounded,
                    color: AppColors.info, size: 15),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Network',
                    style: AppTypography.labelMd,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(device.ip, style: AppTypography.headingSm),
          if (device.model.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(device.model, style: AppTypography.bodySm),
          ],
        ],
      ),
    );
  }
}

// ── Add / Edit form sheet ─────────────────────────────────────────────────────

class _DeviceFormSheet extends StatefulWidget {
  const _DeviceFormSheet({
    required this.existing,
    required this.tapo,
    required this.strings,
    required this.onSave,
  });

  final TapoDevice? existing;
  final TapoService tapo;
  final AppStrings strings;
  final Future<void> Function(TapoDevice device) onSave;

  @override
  State<_DeviceFormSheet> createState() => _DeviceFormSheetState();
}

class _DeviceFormSheetState extends State<_DeviceFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _ipCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passwordCtrl;

  bool _testing = false;
  String? _testResult;
  bool _testSuccess = false;
  bool _obscurePass = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _nameCtrl = TextEditingController(text: d?.name ?? '');
    _ipCtrl = TextEditingController(text: d?.ip ?? '');
    _emailCtrl = TextEditingController(text: d?.email ?? '');
    _passwordCtrl = TextEditingController(text: d?.password ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ipCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _nameCtrl.text.trim().isNotEmpty &&
      _ipCtrl.text.trim().isNotEmpty &&
      _emailCtrl.text.trim().isNotEmpty &&
      _passwordCtrl.text.isNotEmpty;

  Future<void> _testConnection() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final result = await widget.tapo.test(
        ip: _ipCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _testResult = result;
        _testSuccess = result.startsWith('Connected');
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    try {
      final device = TapoDevice(
        id: widget.existing?.id ?? newDeviceId(),
        name: _nameCtrl.text.trim(),
        ip: _ipCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      await widget.onSave(device);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: AppRadius.xsBR,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                widget.existing == null
                    ? 'Add Tapo Device'
                    : 'Edit ${widget.existing!.name}',
                style: AppTypography.headingLg,
              ),
              const SizedBox(height: AppSpacing.xl),

              // Name
              TextField(
                controller: _nameCtrl,
                onChanged: (_) => setState(() {}),
                style: AppTypography.bodyLg,
                decoration: const InputDecoration(
                  labelText: 'Device name',
                  hintText: 'e.g. Garage Charger',
                  prefixIcon: Icon(Icons.label_outline_rounded, size: 18),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // IP
              TextField(
                controller: _ipCtrl,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.url,
                style: AppTypography.bodyLg,
                decoration: const InputDecoration(
                  labelText: 'IP address',
                  hintText: '192.168.1.75',
                  prefixIcon: Icon(Icons.router_rounded, size: 18),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Email
              TextField(
                controller: _emailCtrl,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.emailAddress,
                style: AppTypography.bodyLg,
                decoration: const InputDecoration(
                  labelText: 'TP-Link account e-mail',
                  prefixIcon: Icon(Icons.email_outlined, size: 18),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Password
              TextField(
                controller: _passwordCtrl,
                onChanged: (_) => setState(() {}),
                obscureText: _obscurePass,
                style: AppTypography.bodyLg,
                decoration: InputDecoration(
                  labelText: 'TP-Link account password',
                  prefixIcon:
                      const Icon(Icons.lock_outline_rounded, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Test result banner
              if (_testResult != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: _testSuccess
                        ? AppColors.successSurface
                        : AppColors.errorSurface,
                    borderRadius: AppRadius.mdBR,
                    border: Border.all(
                      color: _testSuccess
                          ? AppColors.success.withValues(alpha:0.3)
                          : AppColors.error.withValues(alpha:0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testSuccess
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 16,
                        color: _testSuccess
                            ? AppColors.success
                            : AppColors.error,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _testResult!,
                          style: AppTypography.bodySm.copyWith(
                            color: _testSuccess
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_ipCtrl.text.trim().isNotEmpty &&
                              _emailCtrl.text.trim().isNotEmpty &&
                              _passwordCtrl.text.isNotEmpty &&
                              !_testing)
                          ? _testConnection
                          : null,
                      icon: _testing
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            )
                          : const Icon(Icons.wifi_find_rounded, size: 18),
                      label: const Text('Test'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: _canSave ? _save : null,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.background,
                              ),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyDevicesView extends StatelessWidget {
  const _EmptyDevicesView({required this.strings, required this.onAdd});
  final AppStrings strings;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.power_outlined,
                size: 48, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.lg),
            Text('No smart plugs yet',
                style: AppTypography.headingMd),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add a TP-Link Tapo plug to control it from here and use it in automations.',
              style: AppTypography.bodyMd,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Tapo device'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}