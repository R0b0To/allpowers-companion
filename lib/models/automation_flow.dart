import 'package:flutter/material.dart';

enum FlowTriggerType { batteryFallsBelow, batteryRisesAbove, tapoPlugState }
enum FlowActionType { wait, setBleOutlet, fireWebhook, controlTapo }
enum BleOutlet { usb, ac, dc }

// ── Trigger ───────────────────────────────────────────────────────────────────

final class FlowTrigger {
  const FlowTrigger({
    required this.type,
    required this.threshold,
    this.windowStart,
    this.windowEnd,
    this.tapoDeviceId,
    this.tapoExpectedOn,
  });

  final FlowTriggerType type;

  /// Used for battery triggers (0–100). Unused for [tapoPlugState].
  final int threshold;

  final TimeOfDay? windowStart;
  final TimeOfDay? windowEnd;

  /// Used for [FlowTriggerType.tapoPlugState] — the device to watch.
  final String? tapoDeviceId;

  /// Used for [FlowTriggerType.tapoPlugState] — fire when plug is this state.
  final bool? tapoExpectedOn;

  bool get hasWindow => windowStart != null && windowEnd != null;

  bool isTimeInWindow(TimeOfDay now) {
    if (!hasWindow) return true;
    final s = windowStart!.hour * 60 + windowStart!.minute;
    final e = windowEnd!.hour * 60 + windowEnd!.minute;
    final n = now.hour * 60 + now.minute;
    return s <= e ? (n >= s && n <= e) : (n >= s || n <= e);
  }

  FlowTrigger copyWith({
    FlowTriggerType? type,
    int? threshold,
    Object? windowStart = _kSentinel,
    Object? windowEnd = _kSentinel,
    Object? tapoDeviceId = _kSentinel,
    Object? tapoExpectedOn = _kSentinel,
  }) =>
      FlowTrigger(
        type: type ?? this.type,
        threshold: threshold ?? this.threshold,
        windowStart: identical(windowStart, _kSentinel)
            ? this.windowStart
            : windowStart as TimeOfDay?,
        windowEnd: identical(windowEnd, _kSentinel)
            ? this.windowEnd
            : windowEnd as TimeOfDay?,
        tapoDeviceId: identical(tapoDeviceId, _kSentinel)
            ? this.tapoDeviceId
            : tapoDeviceId as String?,
        tapoExpectedOn: identical(tapoExpectedOn, _kSentinel)
            ? this.tapoExpectedOn
            : tapoExpectedOn as bool?,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'threshold': threshold,
        if (windowStart != null) 'windowStart': _fmtTime(windowStart!),
        if (windowEnd != null) 'windowEnd': _fmtTime(windowEnd!),
        if (tapoDeviceId != null) 'tapoDeviceId': tapoDeviceId,
        if (tapoExpectedOn != null) 'tapoExpectedOn': tapoExpectedOn,
      };

  static FlowTrigger fromJson(Map<String, dynamic> j) => FlowTrigger(
        type: FlowTriggerType.values.byName(
          j['type'] as String? ?? FlowTriggerType.batteryFallsBelow.name,
        ),
        threshold: (j['threshold'] as num? ?? 20).toInt().clamp(0, 100),
        windowStart: j['windowStart'] != null
            ? _parseTime(j['windowStart'] as String)
            : null,
        windowEnd: j['windowEnd'] != null
            ? _parseTime(j['windowEnd'] as String)
            : null,
        tapoDeviceId: j['tapoDeviceId'] as String?,
        tapoExpectedOn: j['tapoExpectedOn'] as bool?,
      );

  static String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay _parseTime(String s) {
    final p = s.split(':');
    return TimeOfDay(
        hour: int.parse(p[0]).clamp(0, 23),
        minute: int.parse(p[1]).clamp(0, 59));
  }
}

// ── Action ────────────────────────────────────────────────────────────────────

final class FlowAction {
  const FlowAction({
    required this.id,
    required this.type,
    this.waitSeconds = 5,
    this.outlet = BleOutlet.ac,
    this.outletOn = true,
    this.webhookUrl = '',
    this.tapoOn = true,
    this.tapoDeviceId = '',
  });

  final String id;
  final FlowActionType type;
  final int waitSeconds;
  final BleOutlet outlet;
  final bool outletOn;
  final String webhookUrl;
  final bool tapoOn;

  /// ID of the [TapoDevice] to control. Empty string = no device selected.
  final String tapoDeviceId;

  FlowAction copyWith({
    FlowActionType? type,
    int? waitSeconds,
    BleOutlet? outlet,
    bool? outletOn,
    String? webhookUrl,
    bool? tapoOn,
    String? tapoDeviceId,
  }) =>
      FlowAction(
        id: id,
        type: type ?? this.type,
        waitSeconds: waitSeconds ?? this.waitSeconds,
        outlet: outlet ?? this.outlet,
        outletOn: outletOn ?? this.outletOn,
        webhookUrl: webhookUrl ?? this.webhookUrl,
        tapoOn: tapoOn ?? this.tapoOn,
        tapoDeviceId: tapoDeviceId ?? this.tapoDeviceId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'waitSeconds': waitSeconds,
        'outlet': outlet.name,
        'outletOn': outletOn,
        'webhookUrl': webhookUrl,
        'tapoOn': tapoOn,
        'tapoDeviceId': tapoDeviceId,
      };

  static FlowAction fromJson(Map<String, dynamic> j) => FlowAction(
        id: j['id'] as String? ?? newFlowId(),
        type: FlowActionType.values.byName(j['type'] as String),
        waitSeconds: (j['waitSeconds'] as num? ?? 5).toInt().clamp(1, 3600),
        outlet:
            BleOutlet.values.byName(j['outlet'] as String? ?? BleOutlet.ac.name),
        outletOn: j['outletOn'] as bool? ?? true,
        webhookUrl: j['webhookUrl'] as String? ?? '',
        tapoOn: j['tapoOn'] as bool? ?? true,
        tapoDeviceId: j['tapoDeviceId'] as String? ?? '',
      );
}

// ── Flow ──────────────────────────────────────────────────────────────────────

final class AutomationFlow {
  const AutomationFlow({
    required this.id,
    required this.name,
    required this.trigger,
    required this.actions,
    this.enabled = true,
  });

  final String id;
  final String name;
  final bool enabled;
  final FlowTrigger trigger;
  final List<FlowAction> actions;

  AutomationFlow copyWith({
    String? name,
    bool? enabled,
    FlowTrigger? trigger,
    List<FlowAction>? actions,
  }) =>
      AutomationFlow(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        trigger: trigger ?? this.trigger,
        actions: actions ?? this.actions,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'trigger': trigger.toJson(),
        'actions': actions.map((a) => a.toJson()).toList(),
      };

  static AutomationFlow? tryFromJson(Map<String, dynamic> j) {
    try {
      return AutomationFlow(
        id: j['id'] as String,
        name: j['name'] as String,
        enabled: j['enabled'] as bool? ?? true,
        trigger: FlowTrigger.fromJson(j['trigger'] as Map<String, dynamic>),
        actions: (j['actions'] as List<dynamic>)
            .map((a) => FlowAction.fromJson(a as Map<String, dynamic>))
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }
}

// ── Starter templates ─────────────────────────────────────────────────────────

List<AutomationFlow> buildDefaultFlows() => [
      AutomationFlow(
        id: newFlowId(),
        name: 'Start Charging',
        trigger: FlowTrigger(
          type: FlowTriggerType.batteryFallsBelow,
          threshold: 10,
          windowStart: const TimeOfDay(hour: 21, minute: 0),
          windowEnd: const TimeOfDay(hour: 8, minute: 0),
        ),
        actions: [
          FlowAction(
              id: newFlowId(),
              type: FlowActionType.setBleOutlet,
              outlet: BleOutlet.ac,
              outletOn: false),
          FlowAction(
              id: newFlowId(), type: FlowActionType.wait, waitSeconds: 5),
          FlowAction(
              id: newFlowId(),
              type: FlowActionType.setBleOutlet,
              outlet: BleOutlet.ac,
              outletOn: true),
        ],
      ),
      AutomationFlow(
        id: newFlowId(),
        name: 'Stop Charging',
        trigger: FlowTrigger(
          type: FlowTriggerType.batteryRisesAbove,
          threshold: 95,
          windowStart: const TimeOfDay(hour: 21, minute: 0),
          windowEnd: const TimeOfDay(hour: 8, minute: 0),
        ),
        actions: [
          FlowAction(
              id: newFlowId(),
              type: FlowActionType.setBleOutlet,
              outlet: BleOutlet.ac,
              outletOn: true),
        ],
      ),
    ];

var _idCounter = 0;
String newFlowId() =>
    '${DateTime.now().millisecondsSinceEpoch}_${++_idCounter}';

const _kSentinel = Object();