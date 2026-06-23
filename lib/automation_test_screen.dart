import 'dart:async';

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

// ── Simulation direction ──────────────────────────────────────────────────────

enum _SimDirection { drain, charge }

// ── Log helpers ───────────────────────────────────────────────────────────────

enum LogLevel { info, success, warning, error }

class _LogEntry {
  const _LogEntry(
      {required this.time, required this.message, required this.level});
  final String time;
  final String message;
  final LogLevel level;
}

// ── Root screen ───────────────────────────────────────────────────────────────

/// Debug screen for testing the automation engine without a physical BLE
/// connection.  Drop into main.dart's `home:` field during development.
///
/// ## Simulation
/// The "Simulation" card drains or charges the fake battery automatically,
/// calling [AutomationEngine.evaluate] on every step. Watch the Engine State
/// card to see exactly why the engine fires or skips.
///
/// ## Common "failed" diagnosis
/// 1. **chargingTriggered = true** — the engine already fired the ON sequence
///    in a previous run and is waiting for the high threshold. Press
///    "Reset State" to clear it.
/// 2. **sequenceRunning = true** — a previous sequence is still in progress
///    (the real sequence has 5 s + 10 s delays). Wait or restart the app.
/// 3. **Outside time window** — the engine turns the plug ON regardless of
///    thresholds when outside the window. Verify the window covers now.
/// 4. **Stale Tapo session** — press "Reset Tapo Session" then retry.
///
/// Remove this screen before release.
class AutomationTestScreen extends StatefulWidget {
  const AutomationTestScreen({super.key});

  @override
  State<AutomationTestScreen> createState() => _AutomationTestScreenState();
}

class _AutomationTestScreenState extends State<AutomationTestScreen> {
  // ── Services ─────────────────────────────────────────────────────────────
  late final StorageService _storage;
  late final BleService _ble;
  late final WebhookService _webhooks;
  late final TapoService _tapo;
  late final HistoryService _history;
  late final AutomationEngine _automation;

  // ── Settings ──────────────────────────────────────────────────────────────
  AutomationSettings _settings = const AutomationSettings();
  bool _ready = false;

  // ── Text controllers ──────────────────────────────────────────────────────
  late final TextEditingController _onUrlCtrl;
  late final TextEditingController _offUrlCtrl;
  late final TextEditingController _ipCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passwordCtrl;

  // ── Fake BLE state ────────────────────────────────────────────────────────
  int _fakeBattery = 50;
  bool _fakeAcOn = true;

  // ── Evaluate ──────────────────────────────────────────────────────────────
  bool _evaluating = false;

  // ── Simulation ────────────────────────────────────────────────────────────
  bool _simRunning = false;
  _SimDirection _simDirection = _SimDirection.drain;
  int _simSpeedMs = 800; // ms between steps
  int _simSteps = 0;
  Timer? _simTimer;

  // ── Debug / state reset ───────────────────────────────────────────────────
  bool _resettingState = false;
  bool _resettingTapo = false;

  // ── Log ───────────────────────────────────────────────────────────────────
  final List<_LogEntry> _log = [];

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

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

    _appendLog(
      'Engine ready — chargingTriggered=${_automation.debugChargingTriggered}',
      _automation.debugChargingTriggered ? LogLevel.warning : LogLevel.success,
    );
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    _history.removeListener(_onHistoryChanged);
    _ble.dispose();
    _history.dispose();
    for (final c in [
      _onUrlCtrl,
      _offUrlCtrl,
      _ipCtrl,
      _emailCtrl,
      _passwordCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // History listener
  // ─────────────────────────────────────────────────────────────────────────

  void _onHistoryChanged() {
    final entries = _history.entries;
    if (entries.isEmpty) return;
    final latest = entries.first;
    final actionLabel =
        latest.action == HistoryAction.turnOn ? '🟢 ON' : '🔴 OFF';
    final methodLabel = switch (latest.method) {
      ActivationMethod.localTapo => 'local Tapo',
      ActivationMethod.webhook => 'webhook',
      ActivationMethod.none => 'no action configured ⚠️',
    };
    _appendLog(
      '$actionLabel — ${latest.success ? 'success' : 'FAILED'} '
      'via $methodLabel (battery: ${latest.batteryLevel}%)',
      latest.success ? LogLevel.success : LogLevel.error,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Settings helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _update(AutomationSettings s) => setState(() => _settings = s);

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

  // ─────────────────────────────────────────────────────────────────────────
  // Single evaluate
  // ─────────────────────────────────────────────────────────────────────────

  /// Runs one evaluate cycle with the current fake battery. Pass [silent]
  /// to suppress the verbose header log line (used during simulation ticks).
  Future<void> _runEvaluate({bool silent = false}) async {
    if (_evaluating) return;
    _syncFromControllers();
    setState(() => _evaluating = true);

    _ble.status = PowerStationStatus.validated(
      batteryLevel: _fakeBattery,
      inputWatts: _simDirection == _SimDirection.charge && _simRunning ? 120 : 0,
      outputWatts: _simDirection == _SimDirection.drain && _simRunning ? 50 : 0,
      minutesRemaining: 120,
      isUsbOn: false,
      isAcOn: _fakeAcOn,
      isDcOn: false,
    );

    if (!silent) {
      final now = TimeOfDay.now();
      final inWindow = _settings.isTimeInWindow(now);
      _appendLog(
        'evaluate() — battery: $_fakeBattery%  '
        'window: ${_fmt(_settings.startTime)}–${_fmt(_settings.endTime)} '
        '(${inWindow ? 'IN ✓' : 'OUT ✗'})  '
        'chargingTriggered: ${_automation.debugChargingTriggered}',
      );
      if (!inWindow) {
        _appendLog('⏰ Outside window → engine will ensure plug is ON',
            LogLevel.warning);
      }
      if (!_settings.enabled) {
        _appendLog('❌ Automation disabled — engine will skip', LogLevel.warning);
      }
      if (!_settings.hasOnAction) {
        _appendLog('⚠️ No ON action configured', LogLevel.warning);
      }
      if (!_settings.hasOffAction) {
        _appendLog('⚠️ No OFF action configured', LogLevel.warning);
      }
    }

    await _automation.evaluate(_settings);

    if (mounted) {
      setState(() {
        _fakeAcOn = _ble.status.isAcOn;
        _evaluating = false;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Simulation
  // ─────────────────────────────────────────────────────────────────────────

  void _startSimulation() {
    if (_simRunning) return;
    _simSteps = 0;
    final dirLabel =
        _simDirection == _SimDirection.drain ? 'drain ↓' : 'charge ↑';
    _appendLog(
      '▶ Simulation started — $dirLabel  '
      'speed: ${_simSpeedMs}ms/step  '
      'battery: $_fakeBattery%',
    );
    setState(() => _simRunning = true);
    _simTimer =
        Timer.periodic(Duration(milliseconds: _simSpeedMs), _simTick);
  }

  void _stopSimulation({bool auto = false}) {
    _simTimer?.cancel();
    _simTimer = null;
    if (mounted) setState(() => _simRunning = false);
    if (auto) {
      _appendLog(
        '⏹ Simulation ended automatically — battery: $_fakeBattery%  '
        'steps: $_simSteps',
        LogLevel.info,
      );
    } else {
      _appendLog(
        '⏹ Simulation stopped manually — battery: $_fakeBattery%  '
        'steps: $_simSteps',
        LogLevel.info,
      );
    }
  }

  Future<void> _simTick(Timer _) async {
    // Skip this tick if a sequence is in progress — it will complete on its
    // own; no point changing the battery underneath it.
    if (_evaluating) return;

    final next = _simDirection == _SimDirection.drain
        ? _fakeBattery - 1
        : _fakeBattery + 1;

    if (next < 0 || next > 100) {
      _stopSimulation(auto: true);
      return;
    }

    setState(() {
      _fakeBattery = next;
      _simSteps++;
    });

    await _runEvaluate(silent: true);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Debug helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _resetEngineState() async {
    if (_resettingState) return;
    setState(() => _resettingState = true);
    await _automation.debugResetState();
    if (mounted) {
      setState(() => _resettingState = false);
      _appendLog(
        '🔄 Engine state reset — chargingTriggered=false, '
        'fullyChargedHandled=false',
        LogLevel.warning,
      );
    }
  }

  Future<void> _resetTapoSession() async {
    if (_resettingTapo) return;
    final ip = _ipCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (ip.isEmpty || email.isEmpty) {
      _appendLog('⚠️ Fill in IP and email before resetting Tapo session',
          LogLevel.warning);
      return;
    }
    setState(() => _resettingTapo = true);
    _tapo.resetSession(ip: ip, email: email);
    if (mounted) {
      setState(() => _resettingTapo = false);
      _appendLog('🔄 Tapo session cleared — next action will re-handshake',
          LogLevel.warning);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Quick scenarios
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _runScenario(int battery) async {
    _stopSimulation();
    setState(() => _fakeBattery = battery);
    await _runEvaluate();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Log
  // ─────────────────────────────────────────────────────────────────────────

  void _appendLog(String message, [LogLevel level = LogLevel.info]) {
    final now = TimeOfDay.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    if (mounted) {
      setState(() {
        _log.insert(0, _LogEntry(time: time, message: message, level: level));
        if (_log.length > 80) _log.removeLast();
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
            child: CircularProgressIndicator(color: AppColors.teal)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            const Icon(Icons.bug_report_rounded,
                color: AppColors.warning, size: 18),
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
                  // ── Settings ─────────────────────────────────────────────
                  _EditableSettingsCard(
                    settings: _settings,
                    onUrlCtrl: _onUrlCtrl,
                    offUrlCtrl: _offUrlCtrl,
                    ipCtrl: _ipCtrl,
                    emailCtrl: _emailCtrl,
                    passwordCtrl: _passwordCtrl,
                    onToggleEnabled: (v) =>
                        _update(_settings.copyWith(enabled: v)),
                    onToggleLocalTapo: (v) {
                      _syncFromControllers();
                      _update(_settings.copyWith(useLocalTapo: v));
                    },
                    onPickStart: () => _pickTime(true),
                    onPickEnd: () => _pickTime(false),
                    onLowChanged: (v) =>
                        _update(_settings.copyWith(lowThreshold: v)),
                    onHighChanged: (v) =>
                        _update(_settings.copyWith(highThreshold: v)),
                    onTextChanged: _syncFromControllers,
                    fmtTime: _fmt,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Engine State ─────────────────────────────────────────
                  _EngineStateCard(
                    automation: _automation,
                    settings: _settings,
                    onResetState: _resetEngineState,
                    onResetTapo: _resetTapoSession,
                    resettingState: _resettingState,
                    resettingTapo: _resettingTapo,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Fake Status ──────────────────────────────────────────
                  _FakeStatusCard(
                    battery: _fakeBattery,
                    acOn: _fakeAcOn,
                    simRunning: _simRunning,
                    simDirection: _simDirection,
                    onBatteryChanged: (v) {
                      _stopSimulation();
                      setState(() => _fakeBattery = v);
                    },
                    onAcChanged: (v) => setState(() => _fakeAcOn = v),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Simulation ───────────────────────────────────────────
                  _SimulationCard(
                    simRunning: _simRunning,
                    simDirection: _simDirection,
                    simSpeedMs: _simSpeedMs,
                    simSteps: _simSteps,
                    settings: _settings,
                    currentBattery: _fakeBattery,
                    onDirectionChanged: (d) {
                      if (!_simRunning) setState(() => _simDirection = d);
                    },
                    onSpeedChanged: (v) {
                      if (!_simRunning) setState(() => _simSpeedMs = v);
                    },
                    onStartStop: _simRunning
                        ? () => _stopSimulation()
                        : _startSimulation,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Quick Scenarios ──────────────────────────────────────
                  _QuickScenariosCard(
                    lowThreshold: _settings.lowThreshold,
                    highThreshold: _settings.highThreshold,
                    onScenario: _runScenario,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Log ──────────────────────────────────────────────────
                  _LogCard(
                    entries: _log,
                    onClear: () => setState(() => _log.clear()),
                  ),
                ],
              ),
            ),

            // ── Evaluate bar ─────────────────────────────────────────────
            _EvaluateBar(
              evaluating: _evaluating,
              simRunning: _simRunning,
              onEvaluate: _runEvaluate,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Engine State Card ─────────────────────────────────────────────────────────

class _EngineStateCard extends StatelessWidget {
  const _EngineStateCard({
    required this.automation,
    required this.settings,
    required this.onResetState,
    required this.onResetTapo,
    required this.resettingState,
    required this.resettingTapo,
  });

  final AutomationEngine automation;
  final AutomationSettings settings;
  final VoidCallback onResetState;
  final VoidCallback onResetTapo;
  final bool resettingState;
  final bool resettingTapo;

  @override
  Widget build(BuildContext context) {
    final inWindow = settings.isTimeInWindow(TimeOfDay.now());
    final chargingTriggered = automation.debugChargingTriggered;
    final sequenceRunning = automation.debugSequenceRunning;
    final fullyHandled = automation.debugFullyChargedHandled;
    final initialized = automation.debugInitialized;

    return _Card(
      title: 'Engine State',
      icon: Icons.memory_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // State flags grid
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _StatePill(
                label: 'initialized',
                value: initialized,
                trueColor: AppColors.success,
                falseColor: AppColors.error,
              ),
              _StatePill(
                label: 'chargingTriggered',
                value: chargingTriggered,
                // true = waiting for high threshold; only a problem if you
                // didn't expect the ON sequence to have already fired.
                trueColor: AppColors.warning,
                falseColor: AppColors.success,
                trueMeaning: 'ON fired — waiting for high threshold',
                falseMeaning: 'ready to fire ON',
              ),
              _StatePill(
                label: 'sequenceRunning',
                value: sequenceRunning,
                trueColor: AppColors.info,
                falseColor: AppColors.textTertiary,
                trueMeaning: 'sequence in progress',
                falseMeaning: 'idle',
              ),
              _StatePill(
                label: 'fullyChargedHandled',
                value: fullyHandled,
                trueColor: AppColors.warning,
                falseColor: AppColors.textTertiary,
                trueMeaning: 'OFF fired this session',
                falseMeaning: 'ready to fire OFF',
              ),
              _StatePill(
                label: 'time window',
                value: inWindow,
                trueColor: AppColors.success,
                falseColor: AppColors.warning,
                trueMeaning: 'inside — normal logic',
                falseMeaning: 'OUTSIDE — will force plug ON',
              ),
            ],
          ),

          // Diagnosis hint
          if (chargingTriggered && !sequenceRunning) ...[
            const SizedBox(height: AppSpacing.md),
            _HintBanner(
              icon: Icons.lightbulb_outline_rounded,
              color: AppColors.warning,
              message:
                  'chargingTriggered=true is the most common reason the ON '
                  'sequence won\'t fire again. Press Reset State to clear it.',
            ),
          ],
          if (!inWindow) ...[
            const SizedBox(height: AppSpacing.md),
            _HintBanner(
              icon: Icons.schedule_rounded,
              color: AppColors.warning,
              message:
                  'Outside the time window — the engine ignores thresholds '
                  'and forces the plug ON (if not already). Adjust the window '
                  'in Settings to cover the current time.',
            ),
          ],

          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: resettingState ? null : onResetState,
                  icon: resettingState
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('Reset State'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    side: const BorderSide(color: AppColors.warning),
                    textStyle: AppTypography.labelMd
                        .copyWith(color: AppColors.warning),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: resettingTapo ? null : onResetTapo,
                  icon: resettingTapo
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_off_rounded, size: 16),
                  label: const Text('Reset Tapo Session'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.info,
                    side: const BorderSide(color: AppColors.info),
                    textStyle: AppTypography.labelMd
                        .copyWith(color: AppColors.info),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({
    required this.label,
    required this.value,
    required this.trueColor,
    required this.falseColor,
    this.trueMeaning,
    this.falseMeaning,
  });

  final String label;
  final bool value;
  final Color trueColor;
  final Color falseColor;
  final String? trueMeaning;
  final String? falseMeaning;

  @override
  Widget build(BuildContext context) {
    final color = value ? trueColor : falseColor;
    final meaning = value ? trueMeaning : falseMeaning;
    return Tooltip(
      message: meaning ?? (value ? 'true' : 'false'),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: AppRadius.smBR,
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style:
                  AppTypography.labelSm.copyWith(color: color, fontSize: 9),
            ),
            const SizedBox(width: 4),
            Text(
              value ? 'true' : 'false',
              style: AppTypography.mono
                  .copyWith(fontSize: 9, color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintBanner extends StatelessWidget {
  const _HintBanner(
      {required this.icon, required this.color, required this.message});
  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: AppRadius.smBR,
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(message,
                style: AppTypography.labelSm
                    .copyWith(color: color, fontSize: 10)),
          ),
        ],
      ),
    );
  }
}

// ── Simulation Card ───────────────────────────────────────────────────────────

class _SimulationCard extends StatelessWidget {
  const _SimulationCard({
    required this.simRunning,
    required this.simDirection,
    required this.simSpeedMs,
    required this.simSteps,
    required this.settings,
    required this.currentBattery,
    required this.onDirectionChanged,
    required this.onSpeedChanged,
    required this.onStartStop,
  });

  final bool simRunning;
  final _SimDirection simDirection;
  final int simSpeedMs;
  final int simSteps;
  final AutomationSettings settings;
  final int currentBattery;
  final ValueChanged<_SimDirection> onDirectionChanged;
  final ValueChanged<int> onSpeedChanged;
  final VoidCallback onStartStop;

  static const _speeds = <String, int>{
    'Fast (200ms)': 200,
    'Normal (800ms)': 800,
    'Slow (2s)': 2000,
    'Very slow (5s)': 5000,
  };

  String get _goalDescription {
    if (simDirection == _SimDirection.drain) {
      return 'Battery will drain toward ${settings.lowThreshold}% — '
          'engine should turn plug ON';
    } else {
      return 'Battery will charge toward ${settings.highThreshold}% — '
          'engine should turn plug OFF';
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Battery Simulation',
      icon: Icons.science_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Goal hint
          _HintBanner(
            icon: Icons.info_outline_rounded,
            color: AppColors.info,
            message: _goalDescription,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Direction toggle
          Text('Direction', style: AppTypography.labelLg),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _DirectionButton(
                  label: 'Drain ↓',
                  subtitle: 'toward low threshold',
                  selected: simDirection == _SimDirection.drain,
                  color: AppColors.error,
                  disabled: simRunning,
                  onTap: () => onDirectionChanged(_SimDirection.drain),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _DirectionButton(
                  label: 'Charge ↑',
                  subtitle: 'toward high threshold',
                  selected: simDirection == _SimDirection.charge,
                  color: AppColors.success,
                  disabled: simRunning,
                  onTap: () => onDirectionChanged(_SimDirection.charge),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Speed
          Text('Step speed', style: AppTypography.labelLg),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            children: _speeds.entries.map((e) {
              final selected = e.value == simSpeedMs;
              return GestureDetector(
                onTap: simRunning ? null : () => onSpeedChanged(e.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.tealSurface
                        : AppColors.surfaceElevated,
                    borderRadius: AppRadius.smBR,
                    border: Border.all(
                      color: selected
                          ? AppColors.teal.withOpacity(0.5)
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    e.key,
                    style: AppTypography.labelSm.copyWith(
                      color: selected
                          ? AppColors.teal
                          : simRunning
                              ? AppColors.textDisabled
                              : AppColors.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Progress row (only when running)
          if (simRunning) ...[
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.teal),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Running — step $simSteps  battery: $currentBattery%',
                  style: AppTypography.labelMd
                      .copyWith(color: AppColors.teal),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // Start / Stop button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onStartStop,
              icon: Icon(
                simRunning
                    ? Icons.stop_rounded
                    : Icons.play_arrow_rounded,
                size: 18,
              ),
              label: Text(simRunning ? 'Stop Simulation' : 'Start Simulation'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    simRunning ? AppColors.error : AppColors.teal,
                foregroundColor: AppColors.background,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectionButton extends StatelessWidget {
  const _DirectionButton({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final Color color;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = disabled ? AppColors.textDisabled : color;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? effectiveColor.withOpacity(0.1)
              : AppColors.surfaceElevated,
          borderRadius: AppRadius.mdBR,
          border: Border.all(
            color: selected
                ? effectiveColor.withOpacity(0.4)
                : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.headingSm
                  .copyWith(color: selected ? effectiveColor : AppColors.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: AppTypography.bodySm),
          ],
        ),
      ),
    );
  }
}

// ── Fake Status Card ──────────────────────────────────────────────────────────

class _FakeStatusCard extends StatelessWidget {
  const _FakeStatusCard({
    required this.battery,
    required this.acOn,
    required this.simRunning,
    required this.simDirection,
    required this.onBatteryChanged,
    required this.onAcChanged,
  });

  final int battery;
  final bool acOn;
  final bool simRunning;
  final _SimDirection simDirection;
  final ValueChanged<int> onBatteryChanged;
  final ValueChanged<bool> onAcChanged;

  @override
  Widget build(BuildContext context) {
    final battColor = AppColors.batteryColor(battery);
    // Simulate realistic input/output watts based on direction
    final inputW = simRunning && simDirection == _SimDirection.charge ? 120 : 0;
    final outputW = simRunning && simDirection == _SimDirection.drain ? 50 : 0;

    return _Card(
      title: 'Fake Station Status',
      icon: Icons.battery_std_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Battery display
          Row(
            children: [
              Text('Battery: ', style: AppTypography.bodyMd),
              Text(
                '$battery%',
                style: AppTypography.headingSm.copyWith(color: battColor),
              ),
              const Spacer(),
              if (simRunning)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.teal.withOpacity(0.12),
                    borderRadius: AppRadius.xsBR,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                          width: 8,
                          height: 8,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: AppColors.teal)),
                      const SizedBox(width: 4),
                      Text('SIM',
                          style: AppTypography.labelSm
                              .copyWith(color: AppColors.teal)),
                    ],
                  ),
                ),
            ],
          ),
          Slider(
            value: battery.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            activeColor: battColor,
            inactiveColor: AppColors.border,
            onChanged: simRunning ? null : (v) => onBatteryChanged(v.round()),
          ),

          // Power flow
          Row(
            children: [
              _PowerBadge(
                  icon: Icons.arrow_downward_rounded,
                  color: AppColors.success,
                  label: '${inputW}W in'),
              const SizedBox(width: AppSpacing.sm),
              _PowerBadge(
                  icon: Icons.arrow_upward_rounded,
                  color: AppColors.error,
                  label: '${outputW}W out'),
              const Spacer(),
              Text('AC outlet:', style: AppTypography.bodyMd),
              const SizedBox(width: AppSpacing.sm),
              Switch(value: acOn, onChanged: onAcChanged),
              Text(
                acOn ? 'ON' : 'OFF',
                style: AppTypography.headingSm.copyWith(
                    color: acOn ? AppColors.ac : AppColors.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PowerBadge extends StatelessWidget {
  const _PowerBadge(
      {required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: AppRadius.xsBR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: AppTypography.labelSm.copyWith(color: color)),
        ],
      ),
    );
  }
}

// ── Quick Scenarios Card ──────────────────────────────────────────────────────

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
      title: 'Quick Scenarios (single evaluate)',
      icon: Icons.play_arrow_rounded,
      child: Column(
        children: [
          _ScenarioButton(
            label: 'At low threshold ($lowThreshold%)',
            subtitle: 'Should fire plug ON',
            color: AppColors.error,
            onTap: () => onScenario(lowThreshold),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ScenarioButton(
            label: 'At high threshold ($highThreshold%)',
            subtitle: 'Should fire plug OFF',
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
                      style:
                          AppTypography.headingSm.copyWith(color: color)),
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

// ── Editable Settings Card ────────────────────────────────────────────────────

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
          _SwitchRow(
            label: 'Automation enabled',
            subtitle: s.enabled ? 'Engine will run' : 'Engine will skip',
            value: s.enabled,
            onChanged: onToggleEnabled,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),

          Text('Time window', style: AppTypography.labelLg),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _TimeTile(
                    label: 'Start',
                    time: fmtTime(s.startTime),
                    onTap: onPickStart),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _TimeTile(
                    label: 'End',
                    time: fmtTime(s.endTime),
                    onTap: onPickEnd),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _StatusPill(
            label: inWindow
                ? '✅ Currently inside window'
                : '⏰ Currently OUTSIDE window',
            color: inWindow ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),

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

          _SwitchRow(
            label: 'Local Tapo',
            subtitle: 'Enable direct plug control',
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

// ── Log Card ──────────────────────────────────────────────────────────────────

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
                  style:
                      AppTypography.labelMd.copyWith(color: AppColors.teal)),
            ),
      child: entries.isEmpty
          ? Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: Text('Run a scenario or start a simulation',
                    style: AppTypography.bodyMd),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entries
                  .map((e) => Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.time,
                                style: AppTypography.mono.copyWith(
                                    fontSize: 10,
                                    color: AppColors.textTertiary)),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(e.message,
                                  style: AppTypography.mono.copyWith(
                                      fontSize: 11,
                                      color: _color(e.level))),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
    );
  }
}

// ── Evaluate Bar ──────────────────────────────────────────────────────────────

class _EvaluateBar extends StatelessWidget {
  const _EvaluateBar({
    required this.evaluating,
    required this.simRunning,
    required this.onEvaluate,
  });
  final bool evaluating;
  final bool simRunning;
  final VoidCallback onEvaluate;

  @override
  Widget build(BuildContext context) {
    final disabled = evaluating || simRunning;
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
          onPressed: disabled ? null : onEvaluate,
          icon: evaluating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.background),
                )
              : const Icon(Icons.play_arrow_rounded),
          label: Text(
            evaluating
                ? 'Sequence running…'
                : simRunning
                    ? 'Simulation active'
                    : 'Evaluate Once',
          ),
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
        SizedBox(
            width: 80,
            child: Text(label, style: AppTypography.bodyMd)),
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
              Expanded(
                  child: Text(title, style: AppTypography.headingSm)),
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