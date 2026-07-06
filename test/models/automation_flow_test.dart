import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ap_companion/models/automation_flow.dart';

void main() {
  group('FlowTrigger.isTimeInWindow', () {
    test('always true when no window is configured', () {
      const trigger =
          FlowTrigger(type: FlowTriggerType.batteryFallsBelow, threshold: 10);
      expect(trigger.hasWindow, isFalse);
      expect(trigger.isTimeInWindow(const TimeOfDay(hour: 3, minute: 0)), isTrue);
      expect(
          trigger.isTimeInWindow(const TimeOfDay(hour: 23, minute: 59)), isTrue);
    });

    test('normal (non-wrapping) window includes only times inside the range',
        () {
      const trigger = FlowTrigger(
        type: FlowTriggerType.batteryFallsBelow,
        threshold: 10,
        windowStart: TimeOfDay(hour: 8, minute: 0),
        windowEnd: TimeOfDay(hour: 20, minute: 0),
      );

      expect(trigger.isTimeInWindow(const TimeOfDay(hour: 8, minute: 0)), isTrue);
      expect(trigger.isTimeInWindow(const TimeOfDay(hour: 14, minute: 0)), isTrue);
      expect(trigger.isTimeInWindow(const TimeOfDay(hour: 20, minute: 0)), isTrue);
      expect(trigger.isTimeInWindow(const TimeOfDay(hour: 7, minute: 59)), isFalse);
      expect(trigger.isTimeInWindow(const TimeOfDay(hour: 20, minute: 1)), isFalse);
    });

    test('overnight (wrapping) window includes times on either side of midnight',
        () {
      const trigger = FlowTrigger(
        type: FlowTriggerType.batteryFallsBelow,
        threshold: 10,
        windowStart: TimeOfDay(hour: 21, minute: 0),
        windowEnd: TimeOfDay(hour: 8, minute: 0),
      );

      expect(trigger.isTimeInWindow(const TimeOfDay(hour: 23, minute: 0)), isTrue);
      expect(trigger.isTimeInWindow(const TimeOfDay(hour: 2, minute: 0)), isTrue);
      expect(trigger.isTimeInWindow(const TimeOfDay(hour: 8, minute: 0)), isTrue);
      expect(trigger.isTimeInWindow(const TimeOfDay(hour: 21, minute: 0)), isTrue);
      expect(trigger.isTimeInWindow(const TimeOfDay(hour: 12, minute: 0)), isFalse);
    });
  });

  group('FlowTrigger.copyWith', () {
    test('explicit null clears windowStart/windowEnd', () {
      const trigger = FlowTrigger(
        type: FlowTriggerType.batteryFallsBelow,
        threshold: 10,
        windowStart: TimeOfDay(hour: 21, minute: 0),
        windowEnd: TimeOfDay(hour: 8, minute: 0),
      );

      final cleared = trigger.copyWith(windowStart: null, windowEnd: null);

      expect(cleared.hasWindow, isFalse);
      expect(cleared.windowStart, isNull);
      expect(cleared.windowEnd, isNull);
    });

    test('omitting a field leaves its previous value untouched', () {
      const trigger = FlowTrigger(
        type: FlowTriggerType.batteryFallsBelow,
        threshold: 10,
        windowStart: TimeOfDay(hour: 21, minute: 0),
        windowEnd: TimeOfDay(hour: 8, minute: 0),
      );

      final updated = trigger.copyWith(threshold: 20);

      expect(updated.threshold, 20);
      expect(updated.windowStart, const TimeOfDay(hour: 21, minute: 0));
      expect(updated.windowEnd, const TimeOfDay(hour: 8, minute: 0));
    });
  });

  group('FlowTrigger JSON', () {
    test('round-trips all fields including plug-state condition', () {
      const trigger = FlowTrigger(
        type: FlowTriggerType.batteryFallsBelow,
        threshold: 15,
        windowStart: TimeOfDay(hour: 21, minute: 30),
        windowEnd: TimeOfDay(hour: 7, minute: 15),
        tapoDeviceId: 'dev_1',
        tapoExpectedOn: false,
        requirePlugState: true,
      );

      final decoded = FlowTrigger.fromJson(trigger.toJson());

      expect(decoded.type, trigger.type);
      expect(decoded.threshold, trigger.threshold);
      expect(decoded.windowStart, trigger.windowStart);
      expect(decoded.windowEnd, trigger.windowEnd);
      expect(decoded.tapoDeviceId, trigger.tapoDeviceId);
      expect(decoded.tapoExpectedOn, trigger.tapoExpectedOn);
      expect(decoded.requirePlugState, trigger.requirePlugState);
    });

    test('clamps an out-of-range threshold on decode', () {
      final decoded = FlowTrigger.fromJson({
        'type': 'batteryFallsBelow',
        'threshold': 500,
      });

      expect(decoded.threshold, 100);
    });
  });

  group('AutomationFlow JSON', () {
    test('round-trips a flow with multiple actions', () {
      final flow = AutomationFlow(
        id: 'flow_1',
        name: 'Start Charging',
        enabled: false,
        trigger: const FlowTrigger(
            type: FlowTriggerType.batteryFallsBelow, threshold: 10),
        actions: const [
          FlowAction(id: 'a1', type: FlowActionType.wait, waitSeconds: 5),
          FlowAction(
              id: 'a2',
              type: FlowActionType.setBleOutlet,
              outlet: BleOutlet.ac,
              outletOn: true),
          FlowAction(
              id: 'a3',
              type: FlowActionType.controlTapo,
              tapoDeviceId: 'dev_1',
              tapoOn: false),
        ],
      );

      final decoded = AutomationFlow.tryFromJson(flow.toJson());

      expect(decoded, isNotNull);
      expect(decoded!.id, flow.id);
      expect(decoded.name, flow.name);
      expect(decoded.enabled, isFalse);
      expect(decoded.actions, hasLength(3));
      expect(decoded.actions[1].outlet, BleOutlet.ac);
      expect(decoded.actions[2].tapoDeviceId, 'dev_1');
      expect(decoded.actions[2].tapoOn, isFalse);
    });

    test('returns null when the trigger is missing or malformed', () {
      final decoded = AutomationFlow.tryFromJson({
        'id': 'flow_1',
        'name': 'Broken',
        'actions': <dynamic>[],
        // 'trigger' key omitted entirely
      });

      expect(decoded, isNull);
    });

    test('a corrupt action prevents that flow from decoding', () {
      // This documents flow-level behavior: unlike HistoryRepository/
      // FlowRepository, which skip a single corrupt *stored line* and keep
      // the rest, AutomationFlow.tryFromJson requires every action inside
      // one flow to parse — a single bad action invalidates that flow.
      final decoded = AutomationFlow.tryFromJson({
        'id': 'flow_1',
        'name': 'Test',
        'trigger': const FlowTrigger(
                type: FlowTriggerType.batteryFallsBelow, threshold: 10)
            .toJson(),
        'actions': [
          {'id': 'a1', 'type': 'notARealType'},
        ],
      });

      expect(decoded, isNull);
    });
  });

  group('AutomationFlow.copyWith', () {
    test('preserves id and only updates provided fields', () {
      final flow = AutomationFlow(
        id: 'flow_1',
        name: 'Original',
        trigger: const FlowTrigger(
            type: FlowTriggerType.batteryFallsBelow, threshold: 10),
        actions: const [],
      );

      final updated = flow.copyWith(name: 'Renamed', enabled: false);

      expect(updated.id, 'flow_1');
      expect(updated.name, 'Renamed');
      expect(updated.enabled, isFalse);
      expect(updated.trigger.threshold, 10);
    });
  });
}