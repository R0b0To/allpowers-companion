import 'package:flutter/material.dart';

import 'models/automation_settings.dart';
import 'models/automation_history_entry.dart';
import 'models/power_station_status.dart';
import 'services/automation_engine.dart';
import 'services/ble_service.dart';
import 'services/history_service.dart';
import 'services/storage_service.dart';
import 'services/tapo_service.dart';
import 'services/webhook_service.dart';
import 'theme/app_theme.dart';

/// Temporary debug screen — drop into main.dart's home: field to test
/// the automation engine without a physical BLE connection.
///
/// Remove before release.
class AutomationTestScreen extends StatefulWidget {
  const AutomationTestScreen({super.key});

  @override
  State<AutomationTestScreen> createState() => _AutomationTestScreenState();
}

class _AutomationTestScreenState extends State<AutomationTestScreen> {
  late final StorageService _storage;
  late final BleService _ble;
  late final WebhookService _webhooks;
  late final TapoService _tapo;
  late final HistoryService _history;
  late final AutomationEngine _automation;

  AutomationSettings _settings = const AutomationSettings();
  bool _ready = false;
  bool _evaluating = false;

  int _fakeBattery = 100;
  bool _fakeAcOn = true;

  final List<_LogEntry> _log = [];

  late final TextEditingController _onUrlCtrl;
  late final TextEditingController _offUrlCtrl;
  late final TextEditingController _ipCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passwordCtrl;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _storage = StorageService();
    _webhooks = WebhookService();
    _tapo = TapoService();
    _ble = BleService(_storage);
    _history = HistoryService(_storage);
    _automation = AutomationEngine(_ble, _webhooks, _tapo, _storage, _history);

    final loaded = await _storage.loadAutomationSettings();
    _settings = loaded;

    _onUrlCtrl = TextEditingController(text: loaded.tapoOnUrl);
    _offUrlCtrl = TextEditingController(text: loaded.tapoOffUrl);
    _ipCtrl = TextEditingController(text: loaded.tapoIp);
    _emailCtrl = TextEditingController(text: loaded.tapoEmail);
    _passwordCtrl = TextEditingController(text: loaded.tapoPassword);

    await _history.init();
    await _automation.init();
    _history.addListener(_onHistoryChanged);

    if (mounted) setState(() => _ready = true);
  }

  void _onHistoryChanged() {
    final entries = _history.entries;
    if (entries.isEmpty) return;
    final latest = entries.first;
    _appendLog(
      '${latest.action == HistoryAction.turnOn ? '🟢 ON' : '🔴 OFF'} '
      '— ${latest.success ? 'success' : 'failed'} '
      'via ${latest.method.name} '
      '(battery: ${latest.batteryLevel}%)',
      latest.success ? LogLevel.success : LogLevel.error,
    );
  }

  void _appendLog(String message, [LogLevel level = LogLevel.info]) {
    final now = TimeOfDay.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    setState(() {
      _log.insert(0, _LogEntry(time: time, message: message, level: level));
      if (_log.length > 50) _log.removeLast();
    });
  }

  void _update(AutomationSettings updated) => setState(() => _settings = updated);

  void _syncFromControllers() {
    _update(_settings.copyWith(
      tapoOnUrl: _onUrlCtrl.text.trim(),
      tapoOffUrl: _offUrlCtrl.text.trim(),
      tapoIp: _ipCtrl.text.trim(),
      tapoEmail: _emailCtrl.text.trim(),
      tapoPassword: _passwordCtrl.text,
    ));
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _settings.startTime : _settings.endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) =>
          Theme(data: AppTheme.timePickerTheme, child: child!),
    );
    if (picked == null) return;
    _update(isStart
        ? _settings.copyWith(startTime: picked)
        : _settings.copyWith(endTime: picked));
  }

  Future<void> _runEvaluate() async {
    if (_evaluating) return;
    _syncFromControllers();
    setState(() => _evaluating = true);

    _ble.status = PowerStationStatus.validated(
      batteryLevel: _fakeBattery,
      inputWatts: 0,
      outputWatts: 50,
      minutesRemaining: 120,
      isUsbOn: false,
      isAcOn: _fakeAcOn,
      isDcOn: false,
    );

    final now = TimeOfDay.now();
    final inWindow = _settings.isTimeInWindow(now);

    _appendLog(
      'evaluate() — battery: $_fakeBattery%, '
      'time: ${_fmt(now)}, '
      'window: ${_fmt(_settings.startTime)}–${_fmt(_settings.endTime)} '
      '(${inWindow ? 'inside' : 'OUTSIDE'}), '
      'enabled: ${_settings.enabled}',
    );

    if (!inWindow) _appendLog('⏰ Outside time window — engine will return early', LogLevel.warning);
    if (!_settings.enabled) _appendLog('❌ Automation disabled — engine will return early', LogLevel.warning);
    if (!_settings.hasOffAction) _appendLog('⚠️ No OFF action configured', LogLevel.warning);
    if (!_settings.hasOnAction) _appendLog('⚠️ No ON action configured', LogLevel.warning);

    await _automation.evaluate(_settings);

    setState(() {
      _fakeAcOn = _ble.status.isAcOn;
      _evaluating = false;
    });
  }

  Future<void> _runScenario(int battery) async {
    setState(() => _fakeBattery = battery);
    await _runEvaluate();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _history.removeListener(_onHistoryChanged);
    _ble.dispose();
    _history.dispose();
    for (final c in [_onUrlCtrl, _offUrlCtrl, _ipCtrl, _emailCtrl, _passwordCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.teal)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            const Icon(Icons.bug_report_rounded, color: AppColors.warning, size: 18),
            const SizedBox(width: 8),
            Text('Automation Test', style: AppTypography.headingMd),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _EditableSettingsCard(
                    settings: _settings,
                    onUrlCtrl: _onUrlCtrl,
                    offUrlCtrl: _offUrlCtrl,
                    ipCtrl: _ipCtrl,
                    emailCtrl: _emailCtrl,
                    passwordCtrl: _passwordCtrl,
                    onToggleEnabled: (v) => _update(_settings.copyWith(enabled: v)),
                    onToggleLocalTapo: (v) {
                      _syncFromControllers();
                      _update(_settings.copyWith(useLocalTapo: v));
                    },
                    onPickStart: () => _pickTime(true),
                    onPickEnd: () => _pickTime(false),
                    onLowChanged: (v) => _update(_settings.copyWith(lowThreshold: v)),
                    onHighChanged: (v) => _update(_settings.copyWith(highThreshold: v)),
                    onTextChanged: _syncFromControllers,
                    fmtTime: _fmt,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _FakeStatusCard(
                    battery: _fakeBattery,
                    acOn: _fakeAcOn,
                    onBatteryChanged: (v) => setState(() => _fakeBattery = v),
                    onAcChanged: (v) => setState(() => _fakeAcOn = v),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _QuickScenariosCard(
                    lowThreshold: _settings.lowThreshold,
                    highThreshold: _settings.highThreshold,
                    onScenario: _runScenario,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _LogCard(
                    entries: _log,
                    onClear: () => setState(() => _log.clear()),
                  ),
                ],
              ),
            ),
            _EvaluateBar(evaluating: _evaluating, onEvaluate: _runEvaluate),
          ],
        ),
      ),
    );
  }
}

// ── Editable settings card ────────────────────────────────────────────────────

class _EditableSettingsCard extends StatelessWidget {
  const _EditableSettingsCard({
    required this.settings,
    required this.onUrlCtrl,
    required this.offUrlCtrl,
    required this.ipCtrl,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.onToggleEnabled,
    required this.onToggleLocalTapo,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onLowChanged,
    required this.onHighChanged,
    required this.onTextChanged,
    required this.fmtTime,
  });

  final AutomationSettings settings;
  final TextEditingController onUrlCtrl;
  final TextEditingController offUrlCtrl;
  final TextEditingController ipCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final ValueChanged<bool> onToggleEnabled;
  final ValueChanged<bool> onToggleLocalTapo;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final ValueChanged<int> onLowChanged;
  final ValueChanged<int> onHighChanged;
  final VoidCallback onTextChanged;
  final String Function(TimeOfDay) fmtTime;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final inWindow = s.isTimeInWindow(TimeOfDay.now());

    return _Card(
      title: 'Automation Settings',
      icon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Enabled ────────────────────────────────────────────────────────
          _SwitchRow(
            label: 'Automation enabled',
            subtitle: s.enabled ? 'Engine will run' : 'Engine will skip',
            value: s.enabled,
            onChanged: onToggleEnabled,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),

          // ── Time window ────────────────────────────────────────────────────
          Text('Time window', style: AppTypography.labelLg),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _TimeTile(
                  label: 'Start',
                  time: fmtTime(s.startTime),
                  onTap: onPickStart,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _TimeTile(
                  label: 'End',
                  time: fmtTime(s.endTime),
                  onTap: onPickEnd,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _StatusPill(
            label: inWindow ? '✅ Currently inside window' : '⏰ Currently outside window',
            color: inWindow ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),

          // ── Thresholds ─────────────────────────────────────────────────────
          Text('Battery thresholds', style: AppTypography.labelLg),
          const SizedBox(height: AppSpacing.sm),
          _ThresholdSlider(
            label: 'Charge below',
            value: s.lowThreshold,
            color: AppColors.error,
            min: 0,
            max: s.highThreshold - 1,
            onChanged: onLowChanged,
          ),
          _ThresholdSlider(
            label: 'Stop at',
            value: s.highThreshold,
            color: AppColors.success,
            min: s.lowThreshold + 1,
            max: 100,
            onChanged: onHighChanged,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),

          // ── Webhooks ───────────────────────────────────────────────────────
          Text('Webhook URLs', style: AppTypography.labelLg),
          const SizedBox(height: AppSpacing.sm),
          _FieldRow(
            controller: onUrlCtrl,
            label: 'ON webhook URL',
            icon: Icons.power_settings_new_rounded,
            iconColor: AppColors.success,
            onChanged: onTextChanged,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: AppSpacing.sm),
          _FieldRow(
            controller: offUrlCtrl,
            label: 'OFF webhook URL',
            icon: Icons.power_off_rounded,
            iconColor: AppColors.error,
            onChanged: onTextChanged,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),

          // ── Local Tapo ─────────────────────────────────────────────────────
          _SwitchRow(
            label: 'Local Tapo',
            subtitle: 'Enable to use direct plug control',
            value: s.useLocalTapo,
            onChanged: onToggleLocalTapo,
          ),
          if (s.useLocalTapo) ...[
            const SizedBox(height: AppSpacing.md),
            _FieldRow(
              controller: ipCtrl,
              label: 'Plug IP address',
              icon: Icons.router_rounded,
              onChanged: onTextChanged,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: AppSpacing.sm),
            _FieldRow(
              controller: emailCtrl,
              label: 'TP-Link email',
              icon: Icons.email_outlined,
              onChanged: onTextChanged,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: AppSpacing.sm),
            _FieldRow(
              controller: passwordCtrl,
              label: 'TP-Link password',
              icon: Icons.lock_outline_rounded,
              onChanged: onTextChanged,
              obscure: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            _StatusPill(
              label: s.hasLocalTapoCredentials
                  ? '✅ Credentials complete'
                  : '⚠️ Fill in IP, email and password',
              color: s.hasLocalTapoCredentials
                  ? AppColors.success
                  : AppColors.warning,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),

          // ── Action summary ─────────────────────────────────────────────────
          Text('Action summary', style: AppTypography.labelLg),
          const SizedBox(height: AppSpacing.sm),
          _StatusPill(
            label: s.hasOnAction
                ? '✅ ON action ready (${s.hasLocalTapoCredentials ? 'local Tapo' : 'webhook'})'
                : '❌ No ON action — set a webhook URL or enable local Tapo',
            color: s.hasOnAction ? AppColors.success : AppColors.error,
          ),
          const SizedBox(height: AppSpacing.xs),
          _StatusPill(
            label: s.hasOffAction
                ? '✅ OFF action ready (${s.hasLocalTapoCredentials ? 'local Tapo' : 'webhook'})'
                : '❌ No OFF action — set a webhook URL or enable local Tapo',
            color: s.hasOffAction ? AppColors.success : AppColors.error,
          ),
        ],
      ),
    );
  }
}

// ── Fake status ───────────────────────────────────────────────────────────────

class _FakeStatusCard extends StatelessWidget {
  const _FakeStatusCard({
    required this.battery,
    required this.acOn,
    required this.onBatteryChanged,
    required this.onAcChanged,
  });

  final int battery;
  final bool acOn;
  final ValueChanged<int> onBatteryChanged;
  final ValueChanged<bool> onAcChanged;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Fake Station Status',
      icon: Icons.battery_std_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Battery: ', style: AppTypography.bodyMd),
              Text(
                '$battery%',
                style: AppTypography.headingSm
                    .copyWith(color: AppColors.batteryColor(battery)),
              ),
            ],
          ),
          Slider(
            value: battery.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            activeColor: AppColors.batteryColor(battery),
            inactiveColor: AppColors.border,
            onChanged: (v) => onBatteryChanged(v.round()),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Text('AC outlet:', style: AppTypography.bodyMd),
              const Spacer(),
              Switch(value: acOn, onChanged: onAcChanged),
              Text(
                acOn ? 'ON' : 'OFF',
                style: AppTypography.headingSm.copyWith(
                  color: acOn ? AppColors.ac : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Quick scenarios ───────────────────────────────────────────────────────────

class _QuickScenariosCard extends StatelessWidget {
  const _QuickScenariosCard({
    required this.lowThreshold,
    required this.highThreshold,
    required this.onScenario,
  });

  final int lowThreshold;
  final int highThreshold;
  final Future<void> Function(int battery) onScenario;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Quick Scenarios',
      icon: Icons.play_arrow_rounded,
      child: Column(
        children: [
          _ScenarioButton(
            label: 'At low threshold ($lowThreshold%)',
            subtitle: 'Should turn plug ON',
            color: AppColors.error,
            onTap: () => onScenario(lowThreshold),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ScenarioButton(
            label: 'At high threshold ($highThreshold%)',
            subtitle: 'Should turn plug OFF',
            color: AppColors.success,
            onTap: () => onScenario(highThreshold),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ScenarioButton(
            label: 'Mid charge (50%)',
            subtitle: 'Should do nothing',
            color: AppColors.textTertiary,
            onTap: () => onScenario(50),
          ),
        ],
      ),
    );
  }
}

class _ScenarioButton extends StatelessWidget {
  const _ScenarioButton({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: AppRadius.mdBR,
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.play_circle_outline_rounded, color: color, size: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTypography.headingSm.copyWith(color: color)),
                  Text(subtitle, style: AppTypography.bodySm),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Log ───────────────────────────────────────────────────────────────────────

enum LogLevel { info, success, warning, error }

class _LogEntry {
  const _LogEntry({required this.time, required this.message, required this.level});
  final String time;
  final String message;
  final LogLevel level;
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.entries, required this.onClear});
  final List<_LogEntry> entries;
  final VoidCallback onClear;

  Color _color(LogLevel l) => switch (l) {
        LogLevel.info => AppColors.textSecondary,
        LogLevel.success => AppColors.success,
        LogLevel.warning => AppColors.warning,
        LogLevel.error => AppColors.error,
      };

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Engine Log',
      icon: Icons.terminal_rounded,
      trailing: entries.isEmpty
          ? null
          : GestureDetector(
              onTap: onClear,
              child: Text('Clear',
                  style: AppTypography.labelMd.copyWith(color: AppColors.teal)),
            ),
      child: entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: Text('Press Evaluate to run the engine',
                    style: AppTypography.bodyMd),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entries
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.time,
                              style: AppTypography.mono.copyWith(
                                  fontSize: 10, color: AppColors.textTertiary)),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(e.message,
                                style: AppTypography.mono
                                    .copyWith(fontSize: 11, color: _color(e.level))),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

// ── Evaluate bar ──────────────────────────────────────────────────────────────

class _EvaluateBar extends StatelessWidget {
  const _EvaluateBar({required this.evaluating, required this.onEvaluate});
  final bool evaluating;
  final VoidCallback onEvaluate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: evaluating ? null : onEvaluate,
          icon: evaluating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.background),
                )
              : const Icon(Icons.play_arrow_rounded),
          label: Text(evaluating ? 'Running…' : 'Evaluate Now'),
        ),
      ),
    );
  }
}

// ── Shared primitives ─────────────────────────────────────────────────────────

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.headingSm),
              Text(subtitle, style: AppTypography.bodySm),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _ThresholdSlider extends StatelessWidget {
  const _ThresholdSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
    required this.min,
    required this.max,
  });

  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: AppTypography.bodyMd)),
        Expanded(
          child: Slider(
            value: clamped.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: (max - min).clamp(1, 100),
            activeColor: color,
            inactiveColor: AppColors.border,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text('$clamped%',
              style: AppTypography.headingSm.copyWith(color: color),
              textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile(
      {required this.label, required this.time, required this.onTap});
  final String label;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: AppRadius.mdBR,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule_outlined,
                size: 14, color: AppColors.textTertiary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.labelSm),
                  Text(time,
                      style: AppTypography.headingSm
                          .copyWith(color: AppColors.teal)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 14, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.controller,
    required this.label,
    required this.icon,
    required this.onChanged,
    this.iconColor = AppColors.textSecondary,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onChanged;
  final TextInputType keyboardType;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      keyboardType: keyboardType,
      obscureText: obscure,
      style: AppTypography.bodyLg,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: AppRadius.smBR,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: AppTypography.labelMd.copyWith(color: color)),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgBR,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.teal),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(title, style: AppTypography.headingSm)),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}